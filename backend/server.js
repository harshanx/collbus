/**
 * CollBus - Simple Backend Server
 * Run: node server.js
 * Then your app can talk to: http://localhost:3000/api
 */

const http = require('http');

// In-memory storage (data resets when you restart the server)
let buses = [
  { id: '1', busNumber: 'KL-10-AB-1234', route: 'Campus – City' },
  { id: '2', busNumber: 'KL-20-CD-5678', route: 'Campus – Town' },
];

let drivers = [
  { id: '1', driverId: 'D101', name: 'John Doe' },
  { id: '2', driverId: 'D102', name: 'Jane Smith' },
];

const PORT = 3000;

function parseBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        resolve({});
      }
    });
  });
}

function sendJson(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
  res.end(JSON.stringify(data));
}

function sendCorsPreflight(res) {
  res.writeHead(204, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  });
  res.end();
}

async function handleRequest(req, res) {
  // Allow app to call from different origin (CORS)
  if (req.method === 'OPTIONS') {
    return sendCorsPreflight(res);
  }

  const url = req.url || '';
  const path = url.split('?')[0];
  const method = req.method;

  // ========== BUSES ==========
  if (path === '/api/buses' && method === 'GET') {
    return sendJson(res, 200, buses);
  }

  if (path === '/api/buses' && method === 'POST') {
    const body = await parseBody(req);
    const id = String(Date.now());
    const bus = { id, busNumber: body.busNumber || '', route: body.route || '' };
    buses.push(bus);
    return sendJson(res, 200, bus);
  }

  if (path.startsWith('/api/buses/') && method === 'PUT') {
    const id = path.split('/').pop();
    const body = await parseBody(req);
    const bus = buses.find((b) => b.id === id);
    if (!bus) return sendJson(res, 404, { message: 'Bus not found' });
    bus.busNumber = body.busNumber ?? bus.busNumber;
    bus.route = body.route ?? bus.route;
    return sendJson(res, 200, bus);
  }

  if (path.startsWith('/api/buses/') && method === 'DELETE') {
    const id = path.split('/').pop();
    const i = buses.findIndex((b) => b.id === id);
    if (i < 0) return sendJson(res, 404, { message: 'Bus not found' });
    buses.splice(i, 1);
    return sendJson(res, 200, { ok: true });
  }

  // ========== DRIVERS ==========
  if (path === '/api/drivers' && method === 'GET') {
    return sendJson(res, 200, drivers);
  }

  if (path === '/api/drivers' && method === 'POST') {
    const body = await parseBody(req);
    const id = String(Date.now());
    const driver = { id, driverId: body.driverId || '', name: body.name || '' };
    drivers.push(driver);
    return sendJson(res, 200, driver);
  }

  if (path.startsWith('/api/drivers/') && method === 'PUT') {
    const id = path.split('/').pop();
    const body = await parseBody(req);
    const driver = drivers.find((d) => d.id === id);
    if (!driver) return sendJson(res, 404, { message: 'Driver not found' });
    driver.driverId = body.driverId ?? driver.driverId;
    driver.name = body.name ?? driver.name;
    return sendJson(res, 200, driver);
  }

  if (path.startsWith('/api/drivers/') && method === 'DELETE') {
    const id = path.split('/').pop();
    const i = drivers.findIndex((d) => d.id === id);
    if (i < 0) return sendJson(res, 404, { message: 'Driver not found' });
    drivers.splice(i, 1);
    return sendJson(res, 200, { ok: true });
  }

  // Not found
  sendJson(res, 404, { message: 'Not found' });
}

const server = http.createServer(handleRequest);

server.listen(PORT, () => {
  console.log('');
  console.log('  CollBus Backend is running!');
  console.log('  Open: http://localhost:' + PORT);
  console.log('  API:  http://localhost:' + PORT + '/api');
  console.log('');
  console.log('  For Android emulator, use: http://10.0.2.2:' + PORT + '/api');
  console.log('  (Set this in lib/core/constants.dart)');
  console.log('');
});
