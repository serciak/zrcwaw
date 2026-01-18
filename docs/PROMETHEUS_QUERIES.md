# Prometheus Queries - Quick Reference

## Dostęp do Prometheus

- **Lokalnie**: http://localhost:9090
- **AWS**: http://monitoring-alb-xxx.us-east-1.elb.amazonaws.com:9090

## Podstawowe metryki FastAPI

### 1. Liczba requestów

```promql
# Wszystkie requesty (całkowita liczba od startu)
http_requests_total

# Requesty per endpoint
http_requests_total{handler="/api/todos"}
http_requests_total{handler="/api/todos/{todo_id}"}

# Requesty per metoda HTTP
http_requests_total{method="GET"}
http_requests_total{method="POST"}

# Requesty per status code
http_requests_total{status="200"}
http_requests_total{status=~"4.."} # wszystkie 4xx
http_requests_total{status=~"5.."} # wszystkie 5xx
```

### 2. Rate (requesty per sekunda)

```promql
# Rate requestów w ostatnich 5 minutach
rate(http_requests_total[5m])

# Rate per endpoint
sum by (handler) (rate(http_requests_total[5m]))

# Rate per status code
sum by (status) (rate(http_requests_total[5m]))

# Całkowity throughput (req/sec)
sum(rate(http_requests_total[1m]))
```

### 3. Latencja / Response Time

```promql
# P50 (mediana) - 50% requestów jest szybszych
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# P95 - 95% requestów jest szybszych
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# P99 - 99% requestów jest szybszych
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Latencja per endpoint
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler))

# Średni czas odpowiedzi
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])
```

### 4. Error Rate

```promql
# Procent błędów 5xx
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Procent błędów 4xx
sum(rate(http_requests_total{status=~"4.."}[5m])) / sum(rate(http_requests_total[5m]))

# Liczba błędów per endpoint
sum by (handler) (rate(http_requests_total{status=~"5.."}[5m]))
```

### 5. Requesty w trakcie przetwarzania

```promql
# Aktualna liczba requestów w trakcie
http_requests_inprogress

# Max requestów jednocześnie (w ostatniej godzinie)
max_over_time(http_requests_inprogress[1h])
```

## Zaawansowane queries

### Top 5 najwolniejszych endpointów

```promql
topk(5, histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler)))
```

### Top 5 endpointów z największą liczbą requestów

```promql
topk(5, sum by (handler) (rate(http_requests_total[5m])))
```

### Success rate (procent requestów 2xx)

```promql
sum(rate(http_requests_total{status=~"2.."}[5m])) / sum(rate(http_requests_total[5m])) * 100
```

### Porównanie traffic per endpoint (procent całości)

```promql
sum by (handler) (rate(http_requests_total[5m])) / sum(rate(http_requests_total[5m])) * 100
```

### Alert: wysoka latencja (P95 > 1s)

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 1
```

### Alert: wysoki error rate (> 5%)

```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
```

## Prometheus self-monitoring

```promql
# Liczba próbek (samples) w Prometheus
prometheus_tsdb_head_samples

# Rozmiar danych na dysku (bajtach)
prometheus_tsdb_storage_blocks_bytes

# Czas scrape
prometheus_target_interval_length_seconds

# Status targetów
up{job="backend"}
```

## Jak używać Prometheus UI

1. **Graph view** - wykresy w czasie
   - Wybierz zakres czasu (np. Last 1 hour, Last 6 hours)
   - Możesz dodać wiele queries na raz (Add Query)
   
2. **Table view** - aktualne wartości
   - Pokazuje najnowsze wartości metryk
   - Przydatne do sprawdzenia stanu "teraz"

3. **Explore** - interaktywna eksploracja
   - Autocomplete dla metryk i labelów
   - Łatwe filtrowanie

4. **Alerts** - reguły alertów
   - W środowisku produkcyjnym (nie skonfigurowane lokalnie)

## Tipsy

- **Range selector** (`[5m]`, `[1h]`) działa tylko z funkcjami `rate()`, `increase()`, itp.
- **Instant selector** (`http_requests_total`) zwraca aktualną wartość
- **Label matching**:
  - `=` równe
  - `!=` różne
  - `=~` regex match
  - `!~` regex negative match
- **Aggregation**: `sum`, `avg`, `min`, `max`, `count`, `topk`, `bottomk`
- **By clause**: grupowanie po labelach, np. `sum by (handler, status)`

