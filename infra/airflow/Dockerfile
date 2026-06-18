FROM docker:27-cli AS dockercli

FROM apache/airflow:2.9.3-python3.11

USER root

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

USER airflow
