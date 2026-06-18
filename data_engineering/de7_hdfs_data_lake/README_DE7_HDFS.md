# DE-7 HDFS Data Lake

This folder stores the commands used to create the HDFS Data Lake structure.

Layers:

- Bronze: raw events and raw source snapshots
- Silver: cleaned and standardized data
- Gold: analytics-ready dimensions and facts

HDFS folders are created at runtime inside the HDFS container, but this project keeps the script so the structure can be recreated whenever the environment is rebuilt.
