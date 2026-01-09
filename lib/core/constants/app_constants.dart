class AppConstants {
  static const int smsDelaySeconds =
      60; // Delay before sending SMS escalation (60 for production)
  static const int callDelaySeconds =
      300; // Delay before call escalation after SMS sent (300 for production = 5 minutes)
  static const int callCountdownSeconds =
      10; // Countdown before initiating calls
  // Add other constants as needed
  static const double shakeThresholdGravity = 1.53; // FR11: 15 m/s² = 1.53G
  static const int minimumShakeCount = 2; // FR11: 3 shakes
  static const int shakeSlopTimeMS =
      2500; // FR11: 2.5 seconds (middle of 2-3s range)
  static const int shakeCountResetTime = 3000; // FR11: 3 seconds
  static const int countdown = 10; // Countdown before sms escalation
  static const int volumecountdown = 10; // Countdown before volume alert sent
}
