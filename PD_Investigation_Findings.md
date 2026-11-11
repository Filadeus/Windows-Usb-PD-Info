# USB-C PD investigation: Sandberg 420-63B powerbank and HP EliteBook 840 G11

> **Status:** active investigation. Last updated 2026-11-11.
> Captures were recorded with a ChargerLAB **Power-Z** (KM-series) and its PC software, and decoded from the `.sqlite` files in this folder.

## Contents

1. [Summary](#1-summary)
2. [Devices and cables](#2-devices-and-cables)
3. [Capture index](#3-capture-index)
4. [Finding A: intermittent negotiation failure (Sandberg + some sinks)](#4-finding-a-intermittent-negotiation-failure-sandberg--some-sinks)
5. [Finding B: Sandberg C1 never offers more than 60 W](#5-finding-b-sandberg-c1-never-offers-more-than-60-w)
6. [Finding C: other protocol quirks](#6-finding-c-other-protocol-quirks)
7. [Timing and power measurements](#7-timing-and-power-measurements)
8. [Open questions and test plan](#8-open-questions-and-test-plan)
9. [Background: USB-C / PD concepts used here](#9-background-usb-c--pd-concepts-used-here)
10. [How the captures were decoded](#10-how-the-captures-were-decoded)

---

## 1. Summary

There are **two independent problems** with the Sandberg powerbank:

| # | Problem | Most likely cause | Confidence |
|---|---|---|---|
| **A** | When the **Sandberg powers on first**, some sinks never answer its power offers. The Sandberg sends 50 offers (about 8.6 s), gives up and stays at 5 V with no charging | It happens with the **HP (awake)** and the **Anker 737 as a sink**, never with the ASUS, the Oppo or the sleeping HP. Once it happens, the **Sandberg stays stuck even after the sink is unplugged**. Slow 5 V switch-on is **ruled out** as the sole trigger | Pattern confirmed (72 plug-ins). Exact trigger not identified |
| **B** | The Sandberg's "100 W" port (C1) only ever offers **20 V 3 A = 60 W** | The Sandberg **never supplies VCONN**, so it can't read the cable's e-marker. Under the PD spec it must then cap at 3 A | **Confirmed by measurement** |

A **third mode, on the C2 (27 W) port only**, was captured as well. The Sandberg doesn't run PD at all and outputs about 4.6 V, and the laptop falls back to slow 5 V charging (section 4.5).

![Outcome of every plug-in by scenario](charts/01_outcome_by_scenario.png)

These are **not** causes:
- the "Vendor Defined" packets seen before failures (they are the Sandberg's cable check);
- the cables (three different 5 A e-marked cables were tested);
- the laptop restart.

---

## 2. Devices and cables

### Power sources

| Device | Rated USB-C output | What it advertises (captured) |
|---|---|---|
| **Sandberg Powerbank USB-C PD 127W 40000**, item 420-63B, 148 Wh | C1: 5/9/12/15 V 3 A, **20 V 5 A (100 W)**. C2: 27 W. USB-A: 22.5 W. 127 W = C1 + C2 combined ([manual](https://sandberg.world/nl-nl/mt/manual/420-63)) | C1: Fixed 5/9/12/15/20 V **@ 3 A**, PPS 3.3–16 V 3 A, PPS 3.3–21 V 3 A. Flags: DRP, Unconstrained, DRD. **Never 5 A** |
| **Anker 737 PowerCore 24K** (A1289), 86.4 Wh | Each C port: up to 28 V 5 A, 140 W ([Anker](https://service.anker.com/article-description/Introduction-to-the-Anker-737-Power-Bank-24K-A1289)) | Fixed 5/9/12/15 V 3 A, **20 V 5 A**, PPS 3.3–21 V 5 A. Flags: DRP, Unconstrained, DRD, EPR |

### Sinks (laptops)

| Device | USB-C input | Observed |
|---|---|---|
| **HP EliteBook 840 G11**, 56 Wh | Ships with a 65 W USB-C adapter. A 110 W HP USB-C adapter is listed as compatible | Requests 20 V 5 A when offered. Draws up to **4.29 A (about 84 W)** |
| **ASUS ProArt P16 H7606**, 90 Wh | USB-C PD 45–100 W (third-party specs). Barrel adapter 200/240 W | Requests 20 V 5 A when offered. Draws up to **4.58 A (87.5 W)** |

### Cables (decoded e-marker identity)

| Cable | ID Header | Cert (XID) | Cable VDO | Meaning |
|---|---|---|---|---|
| Anker 100 W, 3 m | `18000000` | none | `00086840` | Passive, **5 A**, 20 V, USB 2.0, latency about 2–3 m |
| StarTech | `186014B0` (VID 0x14B0) | `0000340C` | `000A4641` | Passive, **5 A**, **50 V / EPR capable**, USB 3.2 Gen 1 |
| HP OEM (P/N F0KYM-HTN1-533) | `1860228A` (VID 0x228A) | `00000297` (certified) | `00082042` | Passive, **5 A**, 20 V, USB 3.2 Gen 2, about 1 m |

All three cables answer cable-identity requests correctly whenever the requester actually powers VCONN.

---

## 3. Capture index

"Power-Z at laptop" means laptop ← Power-Z ← cable ← powerbank. "At C1" means the Power-Z is plugged into the Sandberg's C1 port.

| File | Setup | Laptop state | Result |
|---|---|---|---|
| `ANKER100W3mCablepd.sqlite` | Sandberg, Anker cable, Power-Z at laptop | Awake | Several failures, 1 OK |
| `ANKER100W3mCableAttempt2pd.sqlite` | Same | Awake | Fails, then OK |
| `ANKER100W3mCableAttempt3Failed_pd.sqlite` | Same | Awake | FAIL |
| `StarTechCable_Success-Fail.sqlite` | Sandberg, StarTech cable | Awake | 2 OK, 2 FAIL |
| `ANKER100W3mCableAfterLaptopRestartpd.sqlite` | Sandberg, Anker cable | **Asleep**, about 90% | 3 of 3 OK |
| `StarTechCable_Success_AfterRestart.sqlite` | Sandberg, StarTech | **Asleep**, about 90% | 3 of 3 OK |
| `ANKER100W3mCableAfterLaptopRestartON50pd.sqlite` | Sandberg, Anker cable | Awake, about 50%, heavy load | 3 OK (2 delayed by about 0.7 s) |
| `ANKER100W3mCableAfterLaptopRestartON_below30pd.sqlite` | Sandberg, Anker cable | Awake, below 30% | **5 FAIL**, 1 OK |
| `ASUSProArtP16ANKER100W3mCablepd.sqlite` | Sandberg → ASUS | Awake | 2 of 2 OK (60 W) |
| `Anker737PowerCore24K/Anker100WCableAnker737PBpd.sqlite` | Anker 737 → HP | Asleep | 3 of 3 OK (100 W) |
| `Anker737PowerCore24K/Anker100WCableAnker737PBAfterRestartONpd.sqlite` | Anker 737 → HP | Awake | 3 of 3 OK |
| `Anker737PowerCore24K/Anker100WCableAnker737PBAfterRestartON100Wpd.sqlite` | Anker 737 ↔ HP | Awake | OK. The laptop sourced first, then a role swap, then 100 W |
| `Anker737PowerCore24K/ANKER100WCableASUSProArtP16pd.sqlite` | Anker 737 → ASUS | Awake | 3 of 3 OK (100 W) |
| `F0KYM-HTN1-533/Sandberg-Ankerpd.sqlite` | HP cable: Sandberg C1 → C2 → C1, then Anker 737 | Awake | C1 OK, C2 no PD, C1 FAIL, C1 OK, Anker OK |
| `F0KYM-HTN1-533/Sandberg3Fails1OK_PowerZ_at_C1pd.sqlite` | **Power-Z at Sandberg C1**, HP cable | Awake | 3 FAIL, 1 OK |
| `F0KYM-HTN1-533/Sandberg3Fails1OK_PowerZ_at_C1_WorstSoFar_27Wpd.sqlite` | Power-Z at **Sandberg C2 (27 W)**, HP cable | Awake | **No PD at all.** The Sandberg outputs about 4.6 V, the laptop's 3 Hard Resets are ignored, the laptop falls back to 5 V (max 13.9 W) and re-attaches every ~10 s (section 4.5) |
| `F0KYM-HTN1-533/Sanberg_several_retries15s_AnkerOKpd.sqlite` | Power-Z at Sandberg C1, HP cable. Laptop side unplugged, **15 s wait** before each replug. Then Anker 737 | Awake | **Sandberg 4 of 4 FAIL** (all Sandberg-first). Anker OK (laptop-first, PR_Swap, 5 A) |
| `F0KYM-HTN1-533/HPEliteBookT2-testpd.sqlite` | **T2**: Power-Z at C1, HP cable, 15 s wait | Awake | First plug-in FAIL. The Sandberg then **stays stuck for 2 minutes** through 4 replugs (section 4.3) |
| `F0KYM-HTN1-533/ASUSProArtP16T4-testpd.sqlite` | **T4**: Sandberg → ASUS, 15 s wait | Awake | **6 of 6 OK**, all Sandberg-first, 20 V 3 A, 55 W |
| `F0KYM-HTN1-533/Sandberg_Charging_Anker737_T5-testpd.sqlite` | **T5**: Sandberg → Anker 737 (as sink), 15 s wait | — | First plug-in FAIL. Same stuck state as the HP, persisting through 4 replugs |
| `F0KYM-HTN1-533/Oppo_T7-OTG-offpd.sqlite` | **T7**: Sandberg → Oppo Find X9 Pro, OTG off | — | **5 of 5 OK**. Uses the Sandberg's **PPS** (about 8.5 V 3 A, up to 26 W) |
| `F0KYM-HTN1-533/Oppo_T7-OTG-onpd.sqlite` | **T7**: same, OTG on | — | **5 of 5 OK**. Fixed 9 V 1.5–2 A |

---

## 4. Finding A: intermittent negotiation failure (Sandberg + some sinks)

### 4.1 What a failure looks like

```
SOP'  Discover_Identity (×3, no reply)          ← Sandberg tries to read the cable (always unanswered)
SOP   Source_Capabilities id=0 (×3, no GoodCRC) ← the laptop does not even send the low-level acknowledgement
SOP   Source_Capabilities id=1 (×3, no GoodCRC)
...   every ~175 ms, 50 times (nCapsCount) ≈ 8.6 s
      → Sandberg gives up, VBUS stays at 5 V, no contract, no Hard Reset, no retry
```

- The laptop sends **no GoodCRC at all**. GoodCRC is the automatic low-level acknowledgement, so the laptop's PD receiver isn't listening.
- It also never sends a Hard Reset, which a sink should do after about 0.6 s without receiving power offers.
- The Sandberg never recovers by itself. Only unplugging and replugging helps.

### 4.2 Electrical signature (seen in every failure)

| Measured | Success | Failure |
|---|---|---|
| Communication CC line after 5 V comes on | about **1.53 V** | about **1.95–2.01 V** |
| Laptop's VCONN-side CC pin (meter at laptop) | 0 V | **0.55 V**: the laptop's own pull-up (Rp) feeding the cable's resistor (Ra), so the laptop is behaving like a power source |
| Sandberg's VCONN-side CC pin (meter at C1) | 0.32 V | **0.85 V** |
| Current at 5 V | 0 mA | **51 mA** for about 0.9 s |

The state appears within one sample (10–40 ms) after the Sandberg switches on 5 V, and in failures it never clears. In the 50% capture it cleared after about 0.57 s, so those plug-ins succeeded late.

![Failed vs successful plug-in timeline](charts/02_timeline_fail_vs_ok.png)

*Left: the Sandberg powers on first, the CC line settles at about 2.0 V and every offer is ignored. Right: the laptop briefly supplies 5 V first, then the Sandberg takes over and the first offer is acknowledged within about 0.1 s.*

### 4.3 What decides success or failure

Both devices are **dual-role (DRP)**: each can supply or take power, and while unconnected they cycle between offering and taking power.

**Laptop side:**

| HP state | Offers power while unconnected? | Failures |
|---|---|---|
| Asleep (Modern Standby) | No, sink only | **Never** (9 of 9 OK) |
| Awake (any battery level) | Yes, about 50% of the time | Yes |

**Sandberg side** (seen with the Power-Z at C1):
- With **nothing attached** (cable unplugged at the Sandberg), it cycles between source and sink for about 5–7 s, then **stays fixed as a source**.
- With **the cable still attached** (unplugged only at the laptop end), it sees the cable's Ra and **keeps cycling indefinitely**: 15–18 s were observed.

**What decides the outcome is which side ends up as the first source:**

| First source | What happens | Result (HP awake) |
|---|---|---|
| **Laptop first** (it catches the Sandberg in its sink phase) | The laptop briefly supplies **5.05–5.10 V**. The Sandberg then flips to source and switches 5 V on **about 80 ms** later | **OK** every time |
| **Sandberg first**, either fixed as source or by winning the cycling race | The Sandberg switches 5 V on **200–440 ms** after the laptop settles as a sink. Its VCONN pin rises 0.32 → 0.86 V | **The HP gets stuck** every time (now 4 of 4 more in the 15 s retry capture) |

- If the cable is unplugged at the Sandberg for more than 7 s, the outcome is **always Sandberg-first, so always fail**.
- If the cable stays attached, it's a random race.

**Other partners, with the Sandberg forced to power on first (tests T2–T7):**

| Sink | Sandberg-first plug-ins | Result | Sandberg 5 V switch-on delay |
|---|---|---|---|
| HP EliteBook (awake) | 22 (all captures) | **20 FAIL**, 2 late OK | 179–521 ms |
| **Anker 737 as sink** | 1 | **FAIL**, same signature (CC 1.98 V / 0.88 V) | 179 ms |
| ASUS ProArt P16 (awake) | 8 | **8 OK** | 220–511 ms |
| Oppo Find X9 Pro, OTG off | 5 | **5 OK** | 179–900 ms |
| Oppo Find X9 Pro, OTG on | 5 | **5 OK** | 890–900 ms |
| HP EliteBook (asleep) | 6 | **6 OK** | 199–522 ms |

What this shows:
- **It isn't HP-specific:** the Anker 737 fails the same way.
- **It isn't the delay:** the ASUS and the Oppo tolerate equal or much longer delays.

**The Sandberg stays stuck after the sink is unplugged (T2, T5).** After the first failed plug-in, the Sandberg kept **VBUS at 5.14 V for the whole 2-minute capture**. It also held the communication CC line at **about 1.94–1.98 V** and its VCONN pin at **0.86–0.88 V**, even during the 15 s periods with the device unplugged and only the cable attached. A normal source in that situation reads about 3.25 V (an open pull-up), detects the detach and switches VBUS off, as it did in T4 and T7.
- Each replug shows a 150 ms dip to about 1.52 V (the new sink's Rd) and then a return to the stuck level.
- The Sandberg sends **no new offers after a replug**.
- Only unplugging the cable **from the Sandberg itself** clears it.

This means the faulty CC level is produced, at least in part, **by the Sandberg**, not only by the sink.

*Caveat: this assumes the device end was unplugged during the 15 s waits, as in the procedure.*

**Below 30%:** plug-ins about 15 s apart meant the Sandberg was always fixed as source, so 5 of 6 failed.

### 4.4 Working hypothesis

> **Revised after tests T2–T7.** When the Sandberg powers on first, its CC interface sometimes enters a faulty state at the moment it switches VBUS on:
> - the communication CC line sits at about **1.95–2.0 V**;
> - its VCONN pin sits at about **0.86 V**;
> - no sink acknowledges its PD messages;
> - it no longer detects detach, so VBUS stays on with nothing attached.
>
> Whether it enters this state depends on the partner. The **awake HP** and the **Anker 737** trigger it; the **ASUS**, the **Oppo** and the **sleeping HP** don't.
>
> The earlier "HP mishandles late VBUS" idea is **not supported**: the Anker fails too, and the ASUS and Oppo tolerate equal or longer delays.

Consistent with the data, though not proven:
- **The partners that trigger it** (HP awake, Anker 737) are devices that also like to be a power source. While awake the HP cycles between offering and taking power, and the Anker as a powerbank is the same. During the Sandberg's attach they may briefly present a source pull-up (Rp), which seems to throw the Sandberg into the faulty state. On the HP side, an Rp was seen on the laptop's VCONN pin during failures (0.55 V).
- **The faulty levels fit a simple model:** both of the Sandberg's CC pins pulled to about 1.95 V through about 1.3 kΩ, instead of a normal 330 µA Rp. That predicts:
  - 1.95 V with nothing attached (measured 1.94 V);
  - about 0.86 V into the cable's Ra (measured 0.86 V);
  - about 1.55 V with only a sink's Rd (measured 1.52 V at the moment of replug).

Not yet known:
- why the ASUS and the Oppo (even with OTG on) don't trigger it;
- whether the Sandberg's malformed CC level is also why sinks can't decode its messages.

![Switch-on delay vs outcome](charts/03_switch_on_delay.png)

*Delay from the sink settling to 5 V switch-on, for plug-ins where the powerbank powered on first. The ASUS and the Oppo negotiate fine with the Sandberg at the same or longer delays, so the slow switch-on is not the trigger on its own.*

### 4.5 Second failure mode: the Sandberg's PD engine is silent

This is a **C2 (27 W port) problem**. Both captures of it are on C2:
- `Sandberg3Fails1OK_PowerZ_at_C1_WorstSoFar_27Wpd.sqlite` (84 s, 7 cycles; the file was recorded on C2 despite its original name);
- `Sandberg-Ankerpd.sqlite`, 1438–1448 s.

It has never been seen on C1.

```
laptop attaches (Rd) → Sandberg turns VBUS on at only ~4.6 V   (vSafe5V min is 4.75 V)
no Source_Capabilities, no SOP' probes – nothing from the Sandberg
laptop: HARD_RESET ×3, ~1.25 s apart   (correct sink behaviour when no offers arrive)
Sandberg ignores them (VBUS never drops to 0 V, which a source must do after a Hard Reset)
laptop falls back to Type-C current: 1.35 → 2.76 A at 4.4–5.0 V (max 13.9 W)
after ~9 s the laptop detaches, re-attaches ~3 s later → loop
```

- Terminations measured at C1: Sandberg Rp (3 A level) on both pins, laptop Rd. So **the Sandberg is the source**.
- Unlike Finding A, the laptop is behaving correctly here.
- Possible trigger: the Sandberg's own state, for example its battery charge level or the aftermath of the previous failures. **Not yet known.**

### 4.6 Workarounds

- Plug in while the laptop is **asleep**, then wake it. This is the only reliable workaround: 9 of 9 OK.
- With the cable kept in the Sandberg, replugging at the laptop is a race the laptop sometimes wins. This only works if the previous attempt didn't leave the Sandberg stuck.
- If it fails, **unplug the cable from the Sandberg** (not just the laptop end): the Sandberg stays stuck otherwise. Then try again.

---

## 5. Finding B: Sandberg C1 never offers more than 60 W

### 5.1 Evidence

- **Every** Sandberg C1 offer, across all captures, both laptops and all three 5 A cables, stops at **20 V 3 A**. The laptops then draw about 2.76 A, which is 92% of the contract: about 54–55 W.
- The PD spec allows offering **more than 3 A only after the source has read the cable's e-marker** and seen "5 A". To read it, the source must power the e-marker with **VCONN**.
- **The Sandberg never supplies VCONN.** Measured on its own VCONN pin, it reads **0.32 V** in successful plug-ins, which is just its pull-up current into the cable's 1 kΩ resistor. In failures it reads **0.85 V**. VCONN would need to be about 3–5.5 V.
- As a result, its SOP' Discover_Identity probes are **never answered**, with any cable.
- When the laptop asks for VCONN (VCONN_Swap), the Sandberg accepts and **never takes VCONN back to re-check the cable**.

### 5.2 How it should work (the Anker 737 with the HP, captured)

```
1. HP sources first (5 V), Anker sinks
2. Anker requests PR_Swap → becomes source
3. Anker offers 20 V 3 A (not VCONN source yet → cable unverified → 3 A max)   ← correct
4. Anker requests VCONN_Swap → becomes VCONN source
5. SOP' Discover_Identity → cable replies "5 A"
6. Anker re-sends Source_Capabilities with 20 V 5 A → HP requests 5 A → ~84 W
```

The Sandberg does step 3 and never steps 4–6.

### 5.3 Measured power

| Source → laptop | Contract | Laptop draws | Power at laptop |
|---|---|---|---|
| Sandberg C1 → HP | 20 V 3 A | 2.76–2.78 A | about 55 W |
| Sandberg C1 → ASUS | 20 V 3 A | 2.76 A | 53.7 W |
| Anker 737 → HP | 20 V 5 A | 4.29–4.32 A | about 84 W |
| Anker 737 → ASUS | 20 V 5 A | 4.58 A | 87.5 W (about 5 W lost in the 3 m cable) |

![Delivered power: Sandberg vs Anker](charts/04_delivered_power.png)

### 5.4 Public reports

Searches in English and Nordic languages found **no** reviews or forum reports of the 420-63 being limited to 60 W, only retailer listings. Item 420-63 is sold as both "PD 100W 38400" and "PD 127W 40000". The unit tested here is a **420-63B**. The box should include a 100 W, 50 cm cable; it wasn't available for testing.

---

## 6. Finding C: other protocol quirks

### Sandberg 420-63B

| Behaviour | Expected | Impact |
|---|---|---|
| Discover_Identity reply in **SVDM v1.0** when asked in v2.1 | Reply in v2.x | Cosmetic |
| ID Header `1900311C`: Power Sink Device + **"PDUSB Host"**, VID 0x311C, cert/product IDs = 0, no DFP VDO | "Power Brick" (or undefined), plus a DFP VDO | Inconsistent identity, not certified |
| Answers `Discover_SVIDs` and `Alert` with **Not_Supported** | NAK for Discover_SVIDs | Cosmetic (the Anker 737 also answers Alert with Not_Supported) |
| SOP' probes at 5 V **without VCONN** | Supply VCONN, or don't probe | Causes Finding B |
| After 50 unanswered offers: silent, stays at 5 V forever | Spec-compliant, but no recovery (for example ErrorRecovery or a VBUS cycle) | Makes Finding A permanent |
| **C2 port:** no PD traffic at all with the HP. The laptop sent 3 Hard Resets, which were ignored. 1.4–1.76 A flowing, **VBUS sagging to 4.21 V** | PD offers, 27 W | Same silent-PD mode as section 4.5. The **Sandberg sources** (the laptop's VCONN pin read 0 V, so the laptop presented Rd only). 4.21 V is below USB's 4.75 V minimum |
| **Ignores Hard Reset** | VBUS must go to 0 V and come back | The laptop's recovery attempts have no effect |

### HP EliteBook 840 G11

| Behaviour | Notes |
|---|---|
| Takes the data host role and VCONN after every contract (DR_Swap, VCONN_Swap) | Normal |
| Sends 3 Alerts per attach: `A2100001`, `22100000`, `02100000` | Battery Status Change + Source Input Change + extended "Power state change", fixed battery 1. Harmless |
| Sometimes sends SOP' Soft_Reset only about 5 ms after taking VCONN. The cable then didn't send Accept, and cable discovery was skipped for that attach | May be too early for the e-marker to start up. Harmless for charging |
| Supplies VCONN at about 3.25 V | Within the 3.0–5.5 V VCONN range |

### Anker 737 (reference behaviour)

- Correct SVDM v2.0 identity: Power Sink Device + **Power Brick**, VID 0x04B4, PID 0xF665, with a DFP VDO.
- NAKs Discover_SVIDs.
- Powers VCONN and reads the cable at 5 V. Re-checks the cable after a role swap.

---

## 7. Timing and power measurements

| Measurement | HP + Sandberg | HP + Anker 737 | ASUS + Sandberg | ASUS + Anker 737 |
|---|---|---|---|---|
| Attach → VBUS on (powerbank as fixed source) | **174–441 ms** | 26–46 ms | 450 ms | ~190 ms |
| VBUS → first **acknowledged** Source_Cap | ~100 ms (OK) / 800 ms (50% case) / never | ~240 ms (first burst at about 60 ms unanswered, retry +185 ms) | 96–100 ms | 237–242 ms |
| Source_Cap → Request (laptop reply time) | **6–7 ms** | **6–7 ms** | **10–12 ms** | **10–12 ms** |
| Request → Accept (powerbank) | 4–8 ms | 3 ms | 6–7 ms | 3 ms |
| Accept → PS_RDY (switch to 20 V) | 85–91 ms | 51–169 ms | 87–91 ms | 52–104 ms |
| Retry interval for unanswered offers | 175 ms | about 185 ms | — | — |

- The laptops' reply time is the **same with either powerbank**: it depends on the laptop, not the source.
- Voltage drop through the 3 m Anker cable is about 0.2–0.25 Ω round trip (for example 20.26 V → 19.13 V at 4.58 A).

---

## 8. Open questions and test plan

### 8.1 Confirm the timing trigger (no meter needed)

| Test | Steps | Prediction if the hypothesis is right |
|---|---|---|
| T1 | HP awake. Unplug **at the Sandberg**, **wait 2 s**, replug. Repeat 5× | Mixed: OK only when the laptop wins the race to source |
| T2 | HP awake. Unplug, **wait 15 s**, replug. Repeat 5× | **Done (twice):** 4 of 4 FAIL; then FAIL, after which the Sandberg stayed stuck through 4 replugs |
| T2b | Like T2, but unplug **at the Sandberg** (forces Sandberg-first) | All FAIL |
| T3 | Like T2, but with the HP asleep | All OK |

### 8.2 Is it HP-specific? (other dual-role sinks against the Sandberg as a fixed source)

| Test | Steps | What it shows |
|---|---|---|
| T4 | **ASUS ProArt P16** awake, T2 procedure (wait 15 s) × 5, Power-Z recording | **Done: 6 of 6 OK** (Sandberg-first, 220–511 ms delays) |
| T5 | **Sandberg C1 → Anker 737** (Anker as the sink), T2 procedure × 5 | **Done: FAIL**, then the Sandberg stayed stuck through 4 replugs. **So it isn't HP-specific** |
| T5b | Repeat T5 and T2, but unplug **the cable from the Sandberg** between attempts, so each attempt starts fresh | Gets 5 independent data points per partner |
| T6 | HP + Anker 737, with the Anker as a fixed source (wait 15 s) | Already OK in the captures. Repeat to rule out chance |
| T7 | **Oppo Find X9 Pro** + Sandberg C1, T2 procedure (wait 15 s) × 5. Once with **OTG off** and once with **OTG on** | **Done: 5 of 5 OK each.** The Sandberg's PPS works (about 8.5 V 3 A, 26 W, OTG off). OTG on used fixed 9 V |

### 8.3 Laptop side

- Run `Collect-UsbPdInfo.ps1` (see `Collect-UsbPdInfo_README.md`). Compare the PD firmware version and the UCSI event log around failures.
- Check for HP BIOS / USB-C PD firmware updates (HP Image Assistant).

---

## 9. Background: USB-C / PD concepts used here

- **CC1 / CC2:** the two configuration pins in the receptacle. One carries the CC wire end to end through the cable, for detection and all PD messages. The other becomes the **VCONN** pin.
- **Rp / Rd / Ra:** pull-up (source), pull-down 5.1 kΩ (sink), and about 1 kΩ (cable e-marker) on CC. The voltage tells each side what's attached and the current level advertised.
- **DRP (dual-role port):** while unconnected, it cycles between Rp and Rd, so it can end up as either source or sink.
- **VCONN:** 3–5.5 V power on the unused CC pin, supplied by the **VCONN source**. It powers the electronics in the cable plug (the e-marker). It is **not** a data lane, and it isn't passed through the cable.
- **E-marker:** the chip in the cable plug that reports current (3 A / 5 A), voltage (20 V / 50 V), speed and so on. A source may offer more than 3 A only after reading "5 A" from it.
- **SOP\* (Start of Packet):** a 4-symbol marker at the start of every PD packet. It works as an address:

  | Type | K-codes | Recipient |
  |---|---|---|
  | SOP | Sync-1 Sync-1 Sync-1 Sync-2 | Port partner |
  | SOP' | Sync-1 Sync-1 Sync-3 Sync-3 | Near cable plug (relative to the VCONN source) |
  | SOP'' | Sync-1 Sync-3 Sync-1 Sync-3 | Far cable plug |
  | Hard Reset | RST-1 RST-1 RST-1 RST-2 | Resets the PD link |
  | Cable Reset | RST-1 Sync-1 RST-1 Sync-3 | Resets the e-marker |

  Only the VCONN source may send SOP'/SOP''. The cable only answers. Each SOP type has its own MessageID counter, and GoodCRC uses the SOP type of the message it acknowledges.
- **Vendor Defined (VDM) Discover_Identity:** structured VDM with SVID 0xFF00. It's used to identify the port partner (SOP) or the cable (SOP'). Power-Z shows it as "Vendor Defined".
- **Key timers:**
  - tCCDebounce: 100–200 ms;
  - VBUS on after attach: up to about 275 ms after debounce;
  - SourceCapabilityTimer: 100–200 ms between offers;
  - nCapsCount: 50 offers;
  - a sink should Hard Reset if no offers arrive within about 620 ms.

---

## 10. How the captures were decoded

- **File format:** `pd_table` holds one row per PD event. The `Raw` blob is laid out as follows:
  - byte 0: flags;
  - bytes 1–4: timestamp in ms (little-endian);
  - byte 5: SOP type (0 = SOP, 1 = SOP', 2 = SOP'') or an event code;
  - then the 16-bit PD header and the 32-bit data objects.

  `pd_chart` holds VBUS, IBUS, CC1 and CC2 samples every 10–80 ms.
- **Retries:** a message repeated 3 times with the same MessageID means **no GoodCRC** was received.
- **The decoder** (`dec.py`, written during this investigation) prints each message with roles, revision, PDOs, RDOs, VDM commands and VDOs. Helper scripts measured the VBUS-edge timing, the CC-state classification and the per-attach success/failure.
- **Where the meter sits matters.** CC readings are taken at the Power-Z, and the VCONN pin seen is the one in **the plug next to the meter**. Readings at the laptop end show the laptop's terminations; readings at C1 show the Sandberg's.
