# Monitoring Stack - Prometheus + Grafana

## Przegląd

Aplikacja Todo posiada zintegrowany monitoring oparty na:
- **Prometheus** - zbieranie i przechowywanie metryk
- **Grafana** - wizualizacja metryk i dashboardy

## Metryki eksponowane przez Backend

Backend FastAPI eksponuje metryki Prometheus na endpoint `/metrics`:

| Metryka | Typ | Opis |
|---------|-----|------|
| `http_requests_total` | Counter | Całkowita liczba żądań HTTP (z etykietami: method, handler, status) |
| `http_request_duration_seconds` | Histogram | Czas odpowiedzi HTTP (percentyle: P50, P95, P99) |
| `http_requests_inprogress` | Gauge | Liczba aktualnie przetwarzanych żądań |

## Lokalny Development

### Uruchomienie

```bash
docker-compose up -d prometheus grafana
```

### Dostęp

- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090

📖 **Zobacz [PROMETHEUS_QUERIES.md](./PROMETHEUS_QUERIES.md) dla pełnego przewodnika po queries**

### Przykładowe queries Prometheus

Aby zobaczyć metryki w Prometheus UI (http://localhost:9090), użyj zakładki **Graph** i wpisz jedno z poniższych zapytań:

```promql
# Wszystkie requesty HTTP (licznik)
http_requests_total

# Requesty per endpoint
http_requests_total{handler="/todos"}

# Rate requestów (req/sec) w ostatnich 5 minutach
rate(http_requests_total[5m])

# Suma requestów per status code
sum by (status) (http_requests_total)

# Suma requestów per endpoint
sum by (handler) (http_requests_total)

# Response time P95 w ostatnich 5 minutach
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Response time per endpoint (P50, P95, P99)
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler))
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler))
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler))

# Requesty w trakcie przetwarzania
http_requests_inprogress

# Error rate (procent błędów 5xx)
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Throughput (requesty per sekunda)
sum(rate(http_requests_total[1m]))
```

**Wskazówki:**
- Kliknij na **Graph** aby zobaczyć wykres w czasie
- Kliknij na **Table** aby zobaczyć aktualne wartości
- Użyj **range selector** (np. `[5m]`, `[1h]`) dla funkcji `rate()` i `increase()`
- Funkcja `rate()` liczy średnią zmianę per sekundę
- Funkcja `histogram_quantile()` liczy percentyle (P50, P95, P99)

## Wdrożenie na AWS (Learners Lab)

### 1. Budowanie obrazów Docker

```bash
# Prometheus
cd prometheus
docker build -t <your-registry>/todos-prometheus:latest .
docker push <your-registry>/todos-prometheus:latest

# Grafana
cd ../grafana
docker build -t <your-registry>/todos-grafana:latest .
docker push <your-registry>/todos-grafana:latest

# Backend (z metrykami)
cd ../backend
docker build -t <your-registry>/todos-backend:latest .
docker push <your-registry>/todos-backend:latest
```

### 2. Konfiguracja Terraform

W pliku `infra/terraform.tfvars`:

```hcl
# Monitoring (Prometheus + Grafana)
prometheus_image       = "<your-registry>/todos-prometheus:latest"
grafana_image          = "<your-registry>/todos-grafana:latest"
grafana_admin_user     = "admin"
grafana_admin_password = "your-secure-password"
```

### 3. Deploy

```bash
cd infra
terraform apply
```

### 4. Dostęp

Po wdrożeniu Terraform wyświetli URLs:

```
grafana_url = "https://monitoring-alb-xxx.us-east-1.elb.amazonaws.com"
prometheus_url = "http://monitoring-alb-xxx.us-east-1.elb.amazonaws.com:9090"
```

## Dashboard

Grafana jest wstępnie skonfigurowana z dashboardem **"Todo App - Backend Metrics"** zawierającym:

1. **Request Rate** - Liczba żądań na sekundę
2. **Response Time (P95)** - 95-ty percentyl czasu odpowiedzi
3. **Requests by Endpoint** - Wykres żądań per endpoint
4. **Response Time by Endpoint** - Latencja per endpoint (P50, P95, P99)
5. **HTTP Status Codes** - Rozkład kodów odpowiedzi HTTP
6. **Requests In Progress** - Aktualnie przetwarzane żądania
7. **Error Rate (5xx)** - Procent błędów serwera

## Architektura na AWS

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Learners Lab                         │
│                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐ │
│  │   Grafana    │────▶│  Prometheus  │────▶│   Backend    │ │
│  │  (Fargate)   │     │  (Fargate)   │     │  (Fargate)   │ │
│  └──────────────┘     └──────────────┘     └──────────────┘ │
│         │                    │                    │         │
│         ▼                    ▼                    ▼         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐ │
│  │   EFS        │     │   EFS        │     │Backend ALB   │ │
│  │ (Grafana DB) │     │ (Prometheus) │     │  (HTTPS)     │ │
│  └──────────────┘     └──────────────┘     └──────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Monitoring ALB                             │ │
│  │   Port 443: Grafana (HTTPS)                            │ │
│  │   Port 9090: Prometheus (HTTP)                         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Zgodność z ograniczeniami Learners Lab

- ✅ Używa **Fargate** (nie EC2)
- ✅ Używa **LabRole** jako task role
- ✅ **EFS** dla persystencji danych
- ✅ **ALB** z self-signed certificate
- ✅ Minimalne zasoby (256 CPU, 512 MB RAM)
- ✅ CloudWatch Logs dla logowania

## Koszty

Szacunkowe koszty (Learners Lab budget):
- ECS Fargate (2 taski): ~$0.10/godzinę
- EFS: ~$0.30/GB/miesiąc
- ALB: ~$0.02/godzinę

**Zalecenie**: Zatrzymaj serwisy gdy nie używasz, aby oszczędzić budżet.

