/**
 * Optional FCM sender for killed-state message/call alerts.
 * Set FCM_SERVER_KEY (legacy server key) on the API host to enable.
 */
const FCM_ENDPOINT = 'https://fcm.googleapis.com/fcm/send';

export async function sendFcmPush(userId, devices, { title, body, data = {}, isCall = false }) {
  const serverKey = process.env.FCM_SERVER_KEY?.trim();
  if (!serverKey) return { sent: 0, skipped: 'NO_FCM_SERVER_KEY' };

  const tokens = (devices ?? [])
    .filter((device) => device.userId === userId && typeof device.pushToken === 'string')
    .map((device) => device.pushToken)
    .filter((token) => token.length >= 8 && !token.startsWith('local-device-'));

  if (tokens.length === 0) return { sent: 0, skipped: 'NO_TOKENS' };

  const payloadData = {
    ...Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, value == null ? '' : String(value)]),
    ),
    title: title ?? '',
    body: body ?? '',
    type: isCall ? 'call' : (data.type ?? 'message'),
  };

  let sent = 0;
  for (const to of tokens) {
    try {
      const response = await fetch(FCM_ENDPOINT, {
        method: 'POST',
        headers: {
          Authorization: `key=${serverKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          to,
          priority: 'high',
          content_available: true,
          // Data + notification so the tray shows when the app is killed,
          // and our Dart background handler can still deep-link on tap.
          notification: {
            title,
            body,
            sound: 'default',
            channel_id: isCall ? 'dating_cloud_calls' : 'dating_cloud_messages',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          data: payloadData,
          android: {
            priority: 'high',
            notification: {
              channel_id: isCall ? 'dating_cloud_calls' : 'dating_cloud_messages',
              sound: 'default',
            },
          },
        }),
      });
      if (response.ok) sent += 1;
      else {
        const text = await response.text();
        console.warn(`FCM send failed (${response.status}): ${text}`);
      }
    } catch (error) {
      console.warn('FCM send error:', error);
    }
  }
  return { sent };
}
