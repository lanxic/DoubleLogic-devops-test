const http = require('http');
const os = require('os');

const instanceId = process.env.INSTANCE_ID || os.hostname();
let requestCount = 0;

const server = http.createServer((req, res) => {
    requestCount++;

    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', instance: instanceId }));
        return;
    }

    // Simulasi beban ringan
    setTimeout(() => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'success',
            instance: instanceId,
            requestCount,
            timestamp: new Date().toISOString(),
            message: `Response from ${instanceId}`
        }));
    }, 100);
});

server.listen(3000, () => {
    console.log(`[${instanceId}] API backend running on port 3000`);
});
