const functions = require('firebase-functions');
const admin = require('firebase-admin');
const sgMail = require('@sendgrid/mail');

// Initialize admin SDK
admin.initializeApp();

// Get Firestore reference
const db = admin.firestore();

// SendGrid API key is expected in environment variable SENDGRID_API_KEY
const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY || functions.config().sendgrid?.api_key;
const SENDGRID_FROM = process.env.SENDGRID_FROM || functions.config().sendgrid?.from;

if (!SENDGRID_API_KEY) {
  console.warn('SENDGRID_API_KEY not set. Email sending will fail until this is configured.');
} else {
  sgMail.setApiKey(SENDGRID_API_KEY);
}

// Configurable: how many OTPs allowed per email in a short window
const OTP_RATE_LIMIT_MAX = 5; // max OTPs
const OTP_RATE_LIMIT_WINDOW_MINUTES = 10; // minutes

// Callable function to request OTPs (safer than allowing direct client writes)
exports.requestOtp = functions.https.onCall(async (data, context) => {
  const email = (data.email || '').toString().trim().toLowerCase();
  const purpose = (data.purpose || 'signup').toString();

  if (!email) {
    throw new functions.https.HttpsError('invalid-argument', 'Email is required');
  }

  // Enforce student domain for signup purpose
  if (purpose === 'signup' && !email.endsWith('@student.nstu.edu.bd')) {
    throw new functions.https.HttpsError('failed-precondition', 'Email must be a student institutional email (@student.nstu.edu.bd)');
  }

  // Rate limiting: check how many OTPs for this email in the time window
  const since = new Date(Date.now() - OTP_RATE_LIMIT_WINDOW_MINUTES * 60 * 1000);
  const recentQ = await admin.firestore().collection('email_otps')
    .where('email', '==', email)
    .where('purpose', '==', purpose)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(since))
    .get();

  if (recentQ.size > OTP_RATE_LIMIT_MAX) {
    // Rate-limited
    return { ok: false, error: 'rate_limited' };
  }

  // Create OTP and optionally send immediately
  const code = (Math.floor(100000 + Math.random() * 900000)).toString();
  const now = new Date();
  const docRef = await admin.firestore().collection('email_otps').add({
    email,
    code,
    purpose,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(now.getTime() + 10 * 60 * 1000)),
  });

  // If sendgrid is not configured we will queue and return code in dev; otherwise attempt to send
  if (!SENDGRID_API_KEY || !SENDGRID_FROM) {
    await docRef.update({ sent: false, queued: true, queuedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { ok: true, dev_code: code };
  }

  // Compose and send email
  try {
    const subject = `Your SafeLink NSTU verification code`;
    const text = `Your verification code is ${code}. It will expire in 10 minutes.`;
    const html = `<p>Your verification code is <strong>${code}</strong>.</p><p>It will expire in 10 minutes.</p>`;

    const msg = {
      to: email,
      from: SENDGRID_FROM,
      subject,
      text,
      html,
    };

    await sgMail.send(msg);
    await docRef.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
    return { ok: true };
  } catch (err) {
    console.error('requestOtp send error', err);
    await docRef.update({ sendError: err.toString(), sendErrorAt: admin.firestore.FieldValue.serverTimestamp() });
    return { ok: false, error: 'send_failed' };
  }
});


exports.sendSignupOtpEmail = functions.firestore
  .document('email_otps/{docId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    try {
      const email = (data.email || '').toString().trim().toLowerCase();
      const code = (data.code || '').toString().trim();
      const purpose = data.purpose || 'signup';

      if (!email || !code) {
        console.log('Invalid OTP document, missing email or code', context.params.docId);
        return null;
      }

      // If already marked sent, skip
      if (data.sent === true) {
        console.log('OTP already sent, skipping', context.params.docId);
        return null;
      }

      // Rate limiting: check how many OTPs for this email in the time window
      const since = new Date(Date.now() - OTP_RATE_LIMIT_WINDOW_MINUTES * 60 * 1000);
      const recentQ = await admin.firestore().collection('email_otps')
        .where('email', '==', email)
        .where('purpose', '==', purpose)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(since))
        .get();

      if (recentQ.size > OTP_RATE_LIMIT_MAX) {
        console.warn(`Rate limit reached for ${email}. Count=${recentQ.size}`);
        await snap.ref.update({ rateLimited: true });
        return null;
      }

      // Compose simple email
      const subject = `Your SafeLink NSTU verification code`;
      const text = `Your verification code is ${code}. It will expire in 10 minutes.`;
      const html = `<p>Your verification code is <strong>${code}</strong>.</p><p>It will expire in 10 minutes.</p>`;

      if (!SENDGRID_API_KEY || !SENDGRID_FROM) {
        console.warn('SendGrid not configured, skipping actual send (dev mode).');
        // Mark sent=false but attach debug hints
        await snap.ref.update({ sent: false, queued: true, queuedAt: admin.firestore.FieldValue.serverTimestamp() });
        return null;
      }

      const msg = {
        to: email,
        from: SENDGRID_FROM,
        subject,
        text,
        html,
      };

      await sgMail.send(msg);
      console.log('OTP email sent to', email);

      // Mark document as sent
      await snap.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
      return null;
    } catch (err) {
      console.error('Error in sendSignupOtpEmail:', err);
      try { await snap.ref.update({ sendError: err.toString(), sendErrorAt: admin.firestore.FieldValue.serverTimestamp() }); } catch (_) {}
      return null;
    }
  });

// ============================================================================
// SOS ALERT SYSTEM - PROCTORIAL BODY NOTIFICATIONS
// ============================================================================

/**
 * HTTP Endpoint: Receive SOS Alert from Student App
 * POST /api/v1/alerts/send
 */
exports.sendSosAlert = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Get alert data from request
    const alertData = req.body;

    console.log('🚨 SOS ALERT RECEIVED FROM STUDENT');
    console.log('Student ID:', alertData.studentId);
    console.log('Student Name:', alertData.studentName);
    console.log('Location:', alertData.location);
    console.log('GPS:', alertData.latitude, alertData.longitude);

    // Validate required fields
    if (!alertData.studentId || !alertData.studentName) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Save alert to global alerts collection for proctorial body
    const alertRef = await db.collection('proctorial_alerts').add({
      ...alertData,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending',
      notificationsSent: false,
    });

    console.log('✅ Alert saved to proctorial_alerts:', alertRef.id);

    // Get all proctorial staff tokens for push notifications from users collection
    const proctorsSnapshot = await db.collection('users')
      .where('role', '==', 'proctorial')
      .get();

    const fcmTokens = [];
    proctorsSnapshot.forEach(doc => {
      const data = doc.data();
      if (data.fcmToken) {
        fcmTokens.push(data.fcmToken);
        console.log(`  📱 Found FCM token for: ${data.email}`);
      }
    });

    console.log(`📊 Total proctorial staff found: ${proctorsSnapshot.size}, with FCM tokens: ${fcmTokens.length}`);

    // Send push notifications to all proctors
    if (fcmTokens.length > 0) {
      const message = {
        notification: {
          title: '🚨 EMERGENCY ALERT',
          body: `${alertData.studentName} (${alertData.studentId}) needs help at ${alertData.location}`,
        },
        data: {
          alertId: alertRef.id,
          studentId: alertData.studentId,
          studentName: alertData.studentName,
          latitude: String(alertData.latitude),
          longitude: String(alertData.longitude),
          type: 'sos_alert',
        },
        tokens: fcmTokens,
      };

      const response = await admin.messaging().sendMulticast(message);
      console.log(`✅ Notifications sent: ${response.successCount} successful, ${response.failureCount} failed`);

      // Update alert with notification status
      await alertRef.update({
        notificationsSent: true,
        notificationCount: response.successCount,
      });
    } else {
      console.log('⚠️ No proctorial staff FCM tokens found');
    }

    // Return success
    return res.status(200).json({
      success: true,
      alertId: alertRef.id,
      message: 'Alert received and proctorial body notified',
      notificationsSent: fcmTokens.length,
    });

  } catch (error) {
    console.error('❌ Error processing SOS alert:', error);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message,
    });
  }
});

/**
 * HTTP Endpoint: Accept Alert (Proctor Response)
 * POST /api/v1/alerts/:alertId/accept
 */
exports.acceptAlert = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const alertId = req.query.alertId || req.body.alertId;
    const proctorName = req.body.proctorName || 'Proctor';
    const proctorId = req.body.proctorId;

    if (!alertId) {
      return res.status(400).json({ error: 'Alert ID required' });
    }

    // Update alert in proctorial_alerts
    await db.collection('proctorial_alerts').doc(alertId).update({
      status: 'accepted',
      respondedByName: proctorName,
      respondedById: proctorId,
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Find student's alert in their personal collection and update it
    const alertDoc = await db.collection('proctorial_alerts').doc(alertId).get();
    const alertData = alertDoc.data();

    if (alertData && alertData.studentId) {
      // Find user by studentId
      const userSnapshot = await db.collection('users')
        .where('studentId', '==', alertData.studentId)
        .limit(1)
        .get();

      if (!userSnapshot.empty) {
        const userId = userSnapshot.docs[0].id;
        
        // Update student's personal alert
        const studentAlertsSnapshot = await db.collection('users')
          .doc(userId)
          .collection('alerts')
          .where('id', '==', alertData.id)
          .limit(1)
          .get();

        if (!studentAlertsSnapshot.empty) {
          await studentAlertsSnapshot.docs[0].ref.update({
            status: 'accepted',
            respondedByName: proctorName,
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Send notification back to student
        const userData = userSnapshot.docs[0].data();
        if (userData.fcmToken) {
          await admin.messaging().send({
            notification: {
              title: '✅ Help is on the way!',
              body: `${proctorName} has accepted your emergency alert and is coming to help.`,
            },
            token: userData.fcmToken,
          });
        }
      }
    }

    console.log(`✅ Alert ${alertId} accepted by ${proctorName}`);

    return res.status(200).json({
      success: true,
      message: 'Alert accepted',
    });

  } catch (error) {
    console.error('❌ Error accepting alert:', error);
    return res.status(500).json({ error: error.message });
  }
});

/**
 * HTTP Endpoint: Reject Alert (Proctor Response)
 * POST /api/v1/alerts/:alertId/reject
 */
exports.rejectAlert = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const alertId = req.query.alertId || req.body.alertId;
    const proctorName = req.body.proctorName || 'Proctor';
    const proctorId = req.body.proctorId;
    const reason = req.body.reason || 'No reason provided';

    if (!alertId) {
      return res.status(400).json({ error: 'Alert ID required' });
    }

    // Update alert in proctorial_alerts
    await db.collection('proctorial_alerts').doc(alertId).update({
      status: 'rejected',
      respondedByName: proctorName,
      respondedById: proctorId,
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      rejectionReason: reason,
    });

    // Update student's personal alert
    const alertDoc = await db.collection('proctorial_alerts').doc(alertId).get();
    const alertData = alertDoc.data();

    if (alertData && alertData.studentId) {
      const userSnapshot = await db.collection('users')
        .where('studentId', '==', alertData.studentId)
        .limit(1)
        .get();

      if (!userSnapshot.empty) {
        const userId = userSnapshot.docs[0].id;
        
        const studentAlertsSnapshot = await db.collection('users')
          .doc(userId)
          .collection('alerts')
          .where('id', '==', alertData.id)
          .limit(1)
          .get();

        if (!studentAlertsSnapshot.empty) {
          await studentAlertsSnapshot.docs[0].ref.update({
            status: 'rejected',
            respondedByName: proctorName,
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Send notification to student
        const userData = userSnapshot.docs[0].data();
        if (userData.fcmToken) {
          await admin.messaging().send({
            notification: {
              title: 'Alert Status Update',
              body: `Your alert was reviewed by ${proctorName}. Reason: ${reason}`,
            },
            token: userData.fcmToken,
          });
        }
      }
    }

    console.log(`❌ Alert ${alertId} rejected by ${proctorName}`);

    return res.status(200).json({
      success: true,
      message: 'Alert rejected',
    });

  } catch (error) {
    console.error('❌ Error rejecting alert:', error);
    return res.status(500).json({ error: error.message });
  }
});

/**
 * HTTP Endpoint: Get All Pending Alerts (for Proctorial Dashboard)
 * GET /api/v1/alerts/pending
 */
exports.getPendingAlerts = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const alertsSnapshot = await db.collection('proctorial_alerts')
      .where('status', '==', 'pending')
      .orderBy('receivedAt', 'desc')
      .limit(50)
      .get();

    const alerts = [];
    alertsSnapshot.forEach(doc => {
      alerts.push({
        id: doc.id,
        ...doc.data(),
      });
    });

    return res.status(200).json({
      success: true,
      count: alerts.length,
      alerts: alerts,
    });

  } catch (error) {
    console.error('❌ Error fetching alerts:', error);
    return res.status(500).json({ error: error.message });
  }
});

/**
 * HTTP Endpoint: Get All Alerts (for Proctorial Dashboard)
 * GET /api/v1/alerts/all
 */
exports.getAllAlerts = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const status = req.query.status; // optional filter
    let query = db.collection('proctorial_alerts').orderBy('receivedAt', 'desc').limit(100);

    if (status) {
      query = query.where('status', '==', status);
    }

    const alertsSnapshot = await query.get();

    const alerts = [];
    alertsSnapshot.forEach(doc => {
      alerts.push({
        id: doc.id,
        ...doc.data(),
      });
    });

    return res.status(200).json({
      success: true,
      count: alerts.length,
      alerts: alerts,
    });

  } catch (error) {
    console.error('❌ Error fetching alerts:', error);
    return res.status(500).json({ error: error.message });
    }
  });
