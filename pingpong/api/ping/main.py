from flask import Flask
from prometheus_client import Counter, generate_latest, Summary, start_http_server
app = Flask(__name__)

#Define Prometheus Metrics
ping_counter = Counter('ping_requests_total', 'Number of ping requests received.')
ping_pong_latency = Summary('ping_pong_request_latency_seconds', 'Latency of ping-pong requests')

@app.route('/ping', methods=['GET'])
def ping():
    ping_counter.inc()
    return 'Pong..\n', 200

#Prometheus Endpoint
@app.route('/metrics')
def metrics():
    return generate_latest(), 200

if __name__ == '__main__':
    print('Ping Service listening on Port 5000...')
    start_http_server(8000)
    app.run(host='0.0.0.0', port=5000)