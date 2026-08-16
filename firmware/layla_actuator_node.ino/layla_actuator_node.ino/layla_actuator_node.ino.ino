#include <Arduino.h>
#include <NimBLEDevice.h>

// --- HARDWARE CONFIGURATION ---
#define BUZZER_PIN          25

// --- BLE SERVICE AND CHARACTERISTIC UUIDs ---
#define SERVICE_UUID        "4fa12345-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "beb54321-1234-1234-1234-123456789abc"

// --- STATE VARIABLES & WATCHDOG CONFIGURATION ---
bool deviceConnected = false;
unsigned long lastPingTime = 0;
const unsigned long WATCHDOG_TIMEOUT = 2500; // 2.5s without data triggers signal loss alert

// --- BLE SERVER CALLBACKS ---
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    lastPingTime = millis();
    // Confirmation double-beep on successful connection
    tone(BUZZER_PIN, 2000, 80);
    delay(100);
    tone(BUZZER_PIN, 2500, 80);
  }

  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    deviceConnected = false;
    // Restart advertising immediately for fast reconnection
    NimBLEDevice::getAdvertising()->start();
    // Low-pitch tone indicating disconnection
    tone(BUZZER_PIN, 800, 300);
  }
};

// --- INCOMING COMMAND CALLBACKS (Web App -> ESP32) ---
class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
    std::string val = pChar->getValue();
    if (val.length() > 0) {
      lastPingTime = millis(); // Reset Watchdog timer on every valid packet
      char cmd = val[0];

      switch (cmd) {
        case 'B': // 'B' = Critical Inclination Alarm (Threshold Exceeded)
          tone(BUZZER_PIN, 3200, 120);
          break;

        case 'C': // 'C' = Level OK Confirmation Tone (Perfect Alignment)
          tone(BUZZER_PIN, 1800, 50);
          break;

        case 'P': // 'P' = Silent Heartbeat Ping (Keeps connection active)
          // No tone emitted, updates Watchdog timer only
          break;

        default:
          break;
      }
    }
  }
};

void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  
  // Power-on self-test tone
  tone(BUZZER_PIN, 1500, 150);

  // Initialize NimBLE stack
  NimBLEDevice::init("LAYLA_ACTUATOR");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Maximum transmission power (+9dBm)

  NimBLEServer* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  
  NimBLECharacteristic* pChar = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  
  pChar->setCallbacks(new CharacteristicCallbacks());
  pService->start();

  // Configure BLE Advertising
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->setName("LAYLA_ACTUATOR");
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->start();
}

void loop() {
  // SAFETY FEATURE: BLE CONNECTION WATCHDOG
  if (deviceConnected) {
    if (millis() - lastPingTime > WATCHDOG_TIMEOUT) {
      // Smartphone lost or application crashed -> Trigger connection warning alert
      tone(BUZZER_PIN, 1000, 200);
      delay(400);
    }
  }
  
  delay(20); // Small delay to allow free RTOS core tasks to yield
}