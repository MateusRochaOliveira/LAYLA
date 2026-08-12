/**
 * @file layla_core.ino
 * @brief LAYLA — Core Embedded Firmware
 * @details Deterministic real-time digital level algorithm featuring IRAM execution,
 *          hardware DLPF, N=5 median filtering, 20 Hz decimated BLE telemetry,
 *          180-degree 2-pass zero calibration endpoint via BLE, and strict zero dynamic memory allocation.
 * @target ESP32 / MPU6050 / Buzzer (GPIO25)
 */

#include <Wire.h>
#include <Preferences.h>
#include <NimBLEDevice.h>
#include <esp_wifi.h>
#include <esp_task_wdt.h>

// ============================================================================
// 1. HARDWARE CONSTANTS AND REGISTERS
// ============================================================================
constexpr uint8_t MPU_ADDR     = 0x68;
constexpr uint8_t CONFIG_REG   = 0x1A; // Digital Low Pass Filter (DLPF) Register
constexpr uint8_t PWR_MGMT_1   = 0x6B;
constexpr uint8_t ACCEL_CONFIG = 0x1C;
constexpr uint8_t ACCEL_XOUT_H = 0x3B;

constexpr uint8_t  PIN_BUZZER  = 25;
constexpr uint32_t BUZZER_FREQ = 2400;

#define SERVICE_UUID        "4fa12345-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "beb54321-1234-1234-1234-123456789abc"

// Scale Constant: 1 / 16384.0f (+/-2g scale)
constexpr float ACCEL_SCALE_FACTOR = 0.00006103515625f;

// ============================================================================
// 2. DATA STRUCTURES (STRICT MEMORY ALIGNMENT)
// ============================================================================
#pragma pack(push, 1)
typedef struct {
  int16_t pitch_scaled; // Pitch * 100 (2 bytes)
  int16_t roll_scaled;  // Roll  * 100 (2 bytes)
} TelemetryPacket;       // Total: 4 exact bytes
#pragma pack(pop)

typedef struct {
  float ax_offset;
  float ay_offset;
  float az_offset;
} CalibrationOffsets;

// Temporary buffers for 2-pass 180-degree calibration
typedef struct {
  float ax_posA, ay_posA, az_posA;
  bool posA_valid;
} CalibrationState;

// ============================================================================
// 3. RING BUFFER STRUCTURE (O(1) STATIC MEMORY)
// ============================================================================
#define BUFFER_SIZE 5

typedef struct {
  float data[BUFFER_SIZE];
  uint8_t head;
  uint8_t count;
} StaticRingBuffer;

inline void IRAM_ATTR ring_buffer_push(StaticRingBuffer *buf, float val) {
  buf->data[buf->head] = val;
  buf->head = (buf->head + 1) % BUFFER_SIZE;
  if (buf->count < BUFFER_SIZE) buf->count++;
}

// ============================================================================
// 4. SORTING ALGORITHM: INSERTION SORT (EXACT MEDIAN FOR N=5)
// ============================================================================
float IRAM_ATTR apply_median_filter(StaticRingBuffer *buf) {
  if (buf->count == 0) return 0.0f;

  float temp[BUFFER_SIZE];

  // Static copy on the stack via raw pointers
  for (uint8_t i = 0; i < buf->count; i++) {
    *(temp + i) = *(buf->data + i);
  }

  // Insertion Sort
  for (uint8_t i = 1; i < buf->count; i++) {
    float key = *(temp + i);
    int8_t j = i - 1;
    while (j >= 0 && *(temp + j) > key) {
      *(temp + j + 1) = *(temp + j);
      j--;
    }
    *(temp + j + 1) = key;
  }

  // For N=5 populated items, index 2 is the exact central median
  return *(temp + (buf->count / 2));
}

// ============================================================================
// 5. SYSTEM STATE (100% STATIC / ZERO HEAP ALLOCATION)
// ============================================================================
static TelemetryPacket currentPacket;
static CalibrationOffsets offsets = {0.0f, 0.0f, 0.0f};
static CalibrationState calState = {0.0f, 0.0f, 0.0f, false};
static Preferences preferences;

static StaticRingBuffer pitchBuffer = {{0}, 0, 0};
static StaticRingBuffer rollBuffer  = {{0}, 0, 0};

static NimBLECharacteristic* pCharacteristic = nullptr;
static bool deviceConnected = false;

static uint32_t lastLoopMicros = 0;
static uint8_t bleDecimator = 0; // Decimator to send BLE telemetry at 20 Hz (100 Hz / 5)

static bool isPerfectLevel = false;

// Forward Declarations
bool read_accel_raw(int16_t *pAx, int16_t *pAy, int16_t *pAz);
void saveCalibration(float ax, float ay, float az);

// ============================================================================
// 6. 180-DEGREE ZERO CALIBRATION LOGIC
// ============================================================================
void captureCalibrationPass(uint8_t pass) {
  int32_t sumX = 0, sumY = 0, sumZ = 0;
  constexpr uint8_t SAMPLES = 64;

  for (uint8_t i = 0; i < SAMPLES; i++) {
    int16_t rx, ry, rz;
    if (read_accel_raw(&rx, &ry, &rz)) {
      sumX += rx;
      sumY += ry;
      sumZ += rz;
    }
    delay(5);
  }

  const float avgX = (sumX / static_cast<float>(SAMPLES)) * ACCEL_SCALE_FACTOR;
  const float avgY = (sumY / static_cast<float>(SAMPLES)) * ACCEL_SCALE_FACTOR;
  const float avgZ = (sumZ / static_cast<float>(SAMPLES)) * ACCEL_SCALE_FACTOR;

  if (pass == 1) {
    calState.ax_posA = avgX;
    calState.ay_posA = avgY;
    calState.az_posA = avgZ;
    calState.posA_valid = true;

    // Single beep for Pass 1 registered
    ledcWrite(PIN_BUZZER, 128); delay(100);
    ledcWrite(PIN_BUZZER, 0);
  } else if (pass == 2 && calState.posA_valid) {
    // 180-degree average calculation cancels out surface inclination error:
    // Offset = (ReadingA + ReadingB) / 2
    const float finalAxOffset = (calState.ax_posA + avgX) / 2.0f;
    const float finalAyOffset = (calState.ay_posA + avgY) / 2.0f;
    // For Z axis, gravity (+1g) is preserved
    const float finalAzOffset = ((calState.az_posA + avgZ) / 2.0f) - 1.0f;

    saveCalibration(finalAxOffset, finalAyOffset, finalAzOffset);
    calState.posA_valid = false;

    // Double success beep for calibration complete
    for (uint8_t i = 0; i < 2; i++) {
      ledcWrite(PIN_BUZZER, 128); delay(100);
      ledcWrite(PIN_BUZZER, 0);   delay(100);
    }
  }
}

// ============================================================================
// 7. STATIC BLE CALLBACKS (ZERO HEAP)
// ============================================================================
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer) override {
    deviceConnected = true;
  }
  void onDisconnect(NimBLEServer* pServer) override {
    deviceConnected = false;
    NimBLEDevice::startAdvertising();
  }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChar) override {
    std::string val = pChar->getValue();
    if (val.length() > 0) {
      const char cmd = val[0];
      if (cmd == '1') {
        captureCalibrationPass(1); // Position A
      } else if (cmd == '2') {
        captureCalibrationPass(2); // Position B (180 deg)
      } else if (cmd == 'R') {
        saveCalibration(0.0f, 0.0f, 0.0f); // Reset offsets
      }
    }
  }
};

static ServerCallbacks serverCallbacks;             // BSS Segment
static CharacteristicCallbacks charCallbacks;       // BSS Segment

// ============================================================================
// 8. INLINED 2D FUZZY ENGINE WITH ANTI-JITTER HYSTERESIS
// ============================================================================
inline float IRAM_ATTR calculateFuzzy2D(float maxErrorDeg) __attribute__((always_inline));

float calculateFuzzy2D(float maxErrorDeg) {
  // Anti-jitter hysteresis for dead-band stability
  if (!isPerfectLevel && maxErrorDeg <= 0.18f) {
    isPerfectLevel = true;
  } else if (isPerfectLevel && maxErrorDeg > 0.23f) {
    isPerfectLevel = false;
  }

  if (isPerfectLevel) return 1.0f;
  if (maxErrorDeg > 2.0f) return 0.0f;

  return 1.0f - ((maxErrorDeg - 0.18f) * 0.549451f); // (1 / 1.82)
}

// ============================================================================
// 9. INITIALIZATION & NVS FUNCTIONS
// ============================================================================
void loadCalibration() {
  preferences.begin("layla_cal", true);
  offsets.ax_offset = preferences.getFloat("ax", 0.0f);
  offsets.ay_offset = preferences.getFloat("ay", 0.0f);
  offsets.az_offset = preferences.getFloat("az", 0.0f);
  preferences.end();
}

void saveCalibration(float ax, float ay, float az) {
  offsets.ax_offset = ax;
  offsets.ay_offset = ay;
  offsets.az_offset = az;

  preferences.begin("layla_cal", false);
  preferences.putFloat("ax", ax);
  preferences.putFloat("ay", ay);
  preferences.putFloat("az", az);
  preferences.end();
}

bool initMPU() {
  Wire.begin();
  Wire.setClock(400000); // 400 kHz Fast I2C

  // 1. Wake up MPU6050
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(PWR_MGMT_1);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) return false;

  // 2. Configure DLPF (Digital Low Pass Filter) to ~21 Hz (attenuates vibrations)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(CONFIG_REG);
  Wire.write(0x04); // DLPF_CFG = 4 (Bandwidth ~21 Hz, Delay 8.5 ms)
  if (Wire.endTransmission() != 0) return false;

  // 3. Configure Accelerometer range to +/-2g
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(ACCEL_CONFIG);
  Wire.write(0x00);
  return (Wire.endTransmission() == 0);
}

void initNimBLE() {
  NimBLEDevice::init("LAYLA_LEVEL");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* pServer = NimBLEDevice::createServer();
  pServer->setServerCallbacks(&serverCallbacks);

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::WRITE
  );

  pCharacteristic->setCallbacks(&charCallbacks);
  pService->start();

  NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();
}

// I2C reading in IRAM with pointer parameter passing
bool IRAM_ATTR read_accel_raw(int16_t *pAx, int16_t *pAy, int16_t *pAz) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) return false;

  if (Wire.requestFrom(static_cast<uint8_t>(MPU_ADDR), static_cast<uint8_t>(6)) == 6) {
    uint8_t rawBytes[6];
    for (uint8_t i = 0; i < 6; i++) {
      rawBytes[i] = Wire.read();
    }

    *pAx = static_cast<int16_t>((rawBytes[0] << 8) | rawBytes[1]);
    *pAy = static_cast<int16_t>((rawBytes[2] << 8) | rawBytes[3]);
    *pAz = static_cast<int16_t>((rawBytes[4] << 8) | rawBytes[5]);

    return true;
  }
  return false;
}

// ============================================================================
// 10. SETUP (COMPATIBLE WITH ESP32 CORE v2 & v3)
// ============================================================================
void setup() {
  setCpuFrequencyMhz(80);
  esp_wifi_stop();

  ledcAttach(PIN_BUZZER, BUZZER_FREQ, 8);
  ledcWrite(PIN_BUZZER, 0);

  if (!initMPU()) {
    while (true) { // Hardware fault sound pattern
      ledcWrite(PIN_BUZZER, 128); delay(50);
      ledcWrite(PIN_BUZZER, 0);   delay(50);
    }
  }

  loadCalibration();
  initNimBLE();

  // Modern Watchdog configuration (ESP32 Arduino Core v3+)
#if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0)
  esp_task_wdt_config_t wdt_config = {
    .timeout_ms = 2000,
    .idle_core_mask = (1 << configNUM_CORES) - 1,
    .trigger_panic = true
  };
  esp_task_wdt_reconfigure(&wdt_config);
  esp_task_wdt_add(NULL);
#else
  esp_task_wdt_init(2, true);
  esp_task_wdt_add(NULL);
#endif

  // Double beep startup indicator
  for (uint8_t i = 0; i < 2; i++) {
    ledcWrite(PIN_BUZZER, 128); delay(30);
    ledcWrite(PIN_BUZZER, 0);   delay(30);
  }

  lastLoopMicros = micros();
}

// ============================================================================
// 11. DETERMINISTIC MAIN LOOP (100 Hz / DRIFT-FREE)
// ============================================================================
void loop() {
  esp_task_wdt_reset();

  const uint32_t nowMicros = micros();

  // Fixed execution every 10,000 us (100 Hz)
  if (nowMicros - lastLoopMicros >= 10000) {
    lastLoopMicros += 10000; // Accumulative advance without drift

    int16_t rawX, rawY, rawZ;

    if (read_accel_raw(&rawX, &rawY, &rawZ)) {
      // Conversion + Offsets
      const float ax = (rawX * ACCEL_SCALE_FACTOR) - offsets.ax_offset;
      const float ay = (rawY * ACCEL_SCALE_FACTOR) - offsets.ay_offset;
      const float az = (rawZ * ACCEL_SCALE_FACTOR) - offsets.az_offset;

      // Trigonometry
      const float pitchRaw = atan2f(ax, sqrtf(ay * ay + az * az)) * RAD_TO_DEG;
      const float rollRaw  = atan2f(ay, sqrtf(ax * ax + az * az)) * RAD_TO_DEG;

      // 1. Ring Buffer insertion (N=5)
      ring_buffer_push(&pitchBuffer, pitchRaw);
      ring_buffer_push(&rollBuffer, rollRaw);

      // 2. Exact Median Filtering
      const float pitchFiltered = apply_median_filter(&pitchBuffer);
      const float rollFiltered  = apply_median_filter(&rollBuffer);

      // 3. Telemetry packet construction
      currentPacket.pitch_scaled = static_cast<int16_t>(pitchFiltered * 100.0f);
      currentPacket.roll_scaled  = static_cast<int16_t>(rollFiltered * 100.0f);

      // 4. DECIMATED BLE TRANSMISSION (Every 5 cycles of 10 ms = 50 ms / 20 Hz)
      bleDecimator++;
      if (bleDecimator >= 5) {
        bleDecimator = 0;

        if (deviceConnected && pCharacteristic != nullptr) {
          const uint8_t *pData = reinterpret_cast<const uint8_t*>(&currentPacket);
          pCharacteristic->setValue(pData, sizeof(TelemetryPacket));
          pCharacteristic->notify();
        }
      }

      // 5. REAL-TIME AUDIO PROCESSING (Kept at 100 Hz)
      const float maxError = (fabsf(pitchFiltered) > fabsf(rollFiltered)) 
                             ? fabsf(pitchFiltered) 
                             : fabsf(rollFiltered);

      const float fuzzyScore = calculateFuzzy2D(maxError);

      if (fuzzyScore >= 0.95f) {
        ledcWrite(PIN_BUZZER, 128); // Continuous tone when level is reached
      } else if (fuzzyScore > 0.05f) {
        const uint32_t pulseInterval = static_cast<uint32_t>(30 + (1.0f - fuzzyScore) * 170);
        const bool state = (millis() / pulseInterval) % 2 == 0;
        ledcWrite(PIN_BUZZER, state ? 128 : 0);
      } else {
        ledcWrite(PIN_BUZZER, 0);
      }
    }
  }
}