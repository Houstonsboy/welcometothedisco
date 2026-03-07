// scripts/migrate_versus.js
const admin = require('firebase-admin');
const serviceAccount = require('./jukebox-996de-firebase-adminsdk-9n2km-3f149867fb.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function migrateVersus() {
  const snapshot = await db.collection('versus').get();

  const batch = db.batch();

  snapshot.docs.forEach((doc) => {
    const data = doc.data();

    batch.update(doc.ref, {
      // add new fields
      createdBy: data['Author'],
      createdAt: data['timestamp'],

      // delete old fields
      Author:    admin.firestore.FieldValue.delete(),
      timestamp: admin.firestore.FieldValue.delete(),
    });
  });

  await batch.commit();
  console.log(`Migrated ${snapshot.docs.length} documents successfully`);
}

migrateVersus().catch(console.error);