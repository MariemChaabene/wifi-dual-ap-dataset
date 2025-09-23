Wi-Fi Performance Monitoring and Dataset Generation
===================================================

1) Project Overview

This project was developed during my M1 engineering internship at Universitat Pompeu Fabra (Barcelona).
It collects Wi-Fi performance metrics from OpenWrt access points and combines them with iPerf traffic
measurements to build structured datasets for analysis and Machine-Learning-based optimization.

Goal:
- Automate monitoring of Wi-Fi parameters (channel, bandwidth, RSSI, retries, throughput, latency, jitter, etc.).
- Merge network metrics with traffic performance data.
- Export clean, analysis-ready datasets (JSONL/CSV).
------------------------------------------------------------------------------------------------------------------------

2) Context

This work is part of a research effort on Wi-Fi optimization using Machine Learning.

Main components:
- OpenWrt-based access points for configuration and monitoring.
- Linux client/server machines for iPerf3 testing.
- Bash and Python scripts for automation, data collection, and analysis.
------------------------------------------------------------------------------------------------------------------------
3) Requirements

- Linux environment (tested on Ubuntu 22.04)
- OpenWrt routers with SSH access enabled
- Python 3.10+
- iPerf3 installed on both client and server machines
- jq and tmux for JSON processing and persistent sessions
------------------------------------------------------------------------------------------------------------------------

4) Architecture (Final Experiment)

The final setup consists of:
- 1 controller machine (runs orchestration scripts).
- 2 OpenWrt access points: AP1 and AP2.
- 2 wired clients: each client is connected by Ethernet to its AP and can SSH into that AP.
- 2 wireless servers: server1 connects to Wi-Fi SSID of AP1; server2 connects to Wi-Fi SSID of AP2.
- 1 Ethernet switch: places the controller and both APs (with their wired clients) on the same LAN.

Reference images (stored in the repo):
- Images/System_Architecture.png
- Images/Commande_Client.jpg
- Images/Commande_Controller.jpg
------------------------------------------------------------------------------------------------------------------------

5) Repository Layout

Exp2/
  └── Exp2.2/
      ├── Scripts/
      │   ├── AP1  root@192.168.1.10/   # Scripts to run from Client1 (wired to AP1) in the AP1 session (via SSH)
      │   ├── AP2  root@192.168.1.2/    # Scripts to run from Client2 (wired to AP2) in the AP2 session (via SSH)
      │   └── Controller/               # Orchestration scripts to run on the controller machine
      └── Exp2.2.ipynb
------------------------------------------------------------------------------------------------------------------------

6) Usage & Reproducibility (Step-by-Step)

A) Place scripts
   - Put all experiment scripts under: Exp2/Exp2.2/Scripts
   - Ensure they are executable: chmod +x *.sh

B) Start iPerf servers (on each wireless server)
   - On server1 (connected to AP1’s Wi-Fi):  iperf3 -s
   - On server2 (connected to AP2’s Wi-Fi):  iperf3 -s
   Keep these running during the whole experiment.

C) Prepare each AP/client side
   - SSH into each AP (or into the wired client that controls the AP).
   - Clean the environment as shown in Images/Commande_Client.jpg (run the listed commands).
   - Launch the collection loop on BOTH AP/client sides:
       ./collect_loop_exp2.sh

D) Prepare the controller
   - On the controller machine, clean the environment as shown in Images/Commande_Controller.jpg.
   - Start the orchestration:
       ./dual_ap_controller.sh

E) Let the experiment run
   - Use tmux/screen_on sessions so processes persist.
   - Keep laptops powered (charger plugged in) and avoid lock/sleep.
   - Periodically verify each server remains connected to the correct AP/SSID.

F) Stop and collect data
   - Stop the loops and controller when the collection window ends.
   - You should obtain a JSONL file such as:
       dataset_dual_ap.jsonl

G) Convert to a flat, analysis-ready dataset
   - Open Exp2/Exp2.2.ipynb (Jupyter Lab).
   - Run the first cell to load dataset_dual_ap.jsonl and produce a flattened CSV/JSONL.
   - Result: a clean dataset ready for EDA/ML (e.g., dataset_dual_ap.csv).
------------------------------------------------------------------------------------------------------------------------

7) Results

- Structured dataset (JSONL/CSV) combining Wi-Fi (OpenWrt) and traffic (iPerf3) metrics.
- Exploratory analysis in Python (Jupyter Lab / pandas).
- Insights on how parameters (channel, bandwidth, MCS, etc.) affect latency, throughput, and stability.
------------------------------------------------------------------------------------------------------------------------

8) Reproducibility Checklist

[ ] iPerf3 servers running on both wireless servers (iperf3 -s)
[ ] collect_loop_exp2.sh running on BOTH AP/client sides
[ ] dual_ap_controller.sh running on the controller
[ ] tmux/screen sessions used everywhere (no terminal loss)
[ ] Power adapters plugged in; no sleep/lock
[ ] Wi-Fi associations verified (server1↔AP1, server2↔AP2)
[ ] dataset_dual_ap.jsonl produced
[ ] Notebook Exp2/Exp2.2.ipynb executed to generate flattened dataset
------------------------------------------------------------------------------------------------------------------------

9) Skills Developed

- Wi-Fi network monitoring & optimization (OpenWrt, iPerf3)
- Bash scripting & automation
- Data structuring and logging (JSONL, CSV)
- Exploratory Data Analysis with Python
- Multi-AP experiment design and orchestration
------------------------------------------------------------------------------------------------------------------------

10) Author

Mariem Chaabene
Final-year Engineering Student — Embedded Systems & IoT — Phelma, Grenoble INP-UGA
LinkedIn: https://www.linkedin.com/in/mariem-chaabene-6569a4287/

For further details, see:
Rapport_de_Stage_Version_Finale_Mariem_Chaabene.pdf


