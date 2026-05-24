const express = require('express');
const mongoose = require('mongoose');

const app = express();
app.use(express.json());

// Local Minikube deployments rely on the in-cluster Mongo service DNS name.
const MONGO_URI = process.env.MONGO_URI || 'mongodb://mongo:27017/devopsdb';

mongoose.connect(MONGO_URI).then(() => {
  console.log('MongoDB connected');
}).catch(err => console.error('MongoDB error:', err));

app.get('/health', (req, res) => {
  const dbState = mongoose.connection.readyState;
  if (dbState === 1) {
    res.json({ status: 'healthy', db: 'connected', version: process.env.APP_VERSION || 'dev' });
  } else {
    res.status(503).json({ status: 'degraded', db: 'disconnected' });
  }
});

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from DevSecOps pipeline!',
    version: process.env.APP_VERSION || 'dev',
    pipeline: 'GitHub Actions → Jenkins → Trivy → Docker Hub → ArgoCD → EKS'
  });
});

const ItemSchema = new mongoose.Schema({ name: String, createdAt: { type: Date, default: Date.now } });
const Item = mongoose.model('Item', ItemSchema);

app.get('/items', async (req, res) => {
  try {
    const items = await Item.find().limit(10);
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/items', async (req, res) => {
  try {
    const item = new Item({ name: req.body.name });
    await item.save();
    res.status(201).json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
