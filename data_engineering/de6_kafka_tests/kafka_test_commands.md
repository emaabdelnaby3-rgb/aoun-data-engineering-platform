# DE-6 Kafka Event Testing Commands

## List Kafka topics
docker exec -it ucp_kafka kafka-topics --bootstrap-server kafka:29092 --list

## Read Food Bank source outbox events
docker exec -it ucp_kafka kafka-console-consumer `
  --bootstrap-server kafka:29092 `
  --topic food_bank.charity_food_bank_operational.dbo.source_event_outbox `
  --from-beginning `
  --max-messages 5

## Read Resala source outbox events
docker exec -it ucp_kafka kafka-console-consumer `
  --bootstrap-server kafka:29092 `
  --topic resala.charity_resala_operational.dbo.source_event_outbox `
  --from-beginning `
  --max-messages 5

## Read Haya Karima source outbox events
docker exec -it ucp_kafka kafka-console-consumer `
  --bootstrap-server kafka:29092 `
  --topic haya_karima.charity_haya_karima_operational.dbo.source_event_outbox `
  --from-beginning `
  --max-messages 5

## Real-time CDC update test in SSMS
USE charity_food_bank_operational;
GO

UPDATE TOP (1) dbo.source_event_outbox
SET event_status =
    CASE 
        WHEN event_status = 'PENDING' THEN 'DEBEZIUM_TEST'
        ELSE 'PENDING'
    END
WHERE event_status IS NOT NULL;
GO

## Expected result in Kafka
"op":"u"

Meaning:
u = update event captured in real time from SQL Server CDC through Debezium into Kafka.
