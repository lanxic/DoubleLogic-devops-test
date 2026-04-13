const http = require('http');

const parkingZones = JSON.stringify({
    status: "success",
    data: [
        { id: 1, name: "Zona A", slots: 150 },
        { id: 2, name: "Zona B", slots: 200 }
    ]
});

const server = http.createServer((req, res) => {
    // Simulasi delay backend 500ms agar efek caching terlihat
    setTimeout(() => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(parkingZones);
    }, 500);
});

server.listen(3000, () => console.log('API Backend jalan di port 3000'));