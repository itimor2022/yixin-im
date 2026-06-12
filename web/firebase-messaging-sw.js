importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: "AIzaSyATpSnaDhQZSGm3Edi4AueB3LuhEZiA8Kw",
  authDomain: "imtest-1d769.firebaseapp.com",
  projectId: "imtest-1d769",
  storageBucket: "imtest-1d769.firebasestorage.app",
  messagingSenderId: "636608823824",
  appId: "1:636608823824:web:6b6daec69629b4dc3d4095",
  measurementId: "G-STQ0D4D6TY"
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.title || '新消息';
  const body  = payload.notification?.body  || payload.data?.body  || '您有一条新消息';

  const notificationOptions = {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.data?.chat_id || 'yixin-message',
    data: payload.data || {},
    vibrate: [200, 100, 200],
    requireInteraction: false,
  };

  // 通知所有页面播放声音
  self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
    for (const client of clientList) {
      client.postMessage({ type: 'FCM_BACKGROUND_MESSAGE', data: payload.data });
    }
  });

  return self.registration.showNotification(title, notificationOptions);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const chatId = event.notification.data?.chat_id;
  const url = chatId ? `/?chat_id=${chatId}` : '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.postMessage({ type: 'NOTIFICATION_CLICK', data: event.notification.data });
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
