#!/usr/bin/env python3
"""Generate realistic retail store ops PDFs for the SharePoint Openflow demo."""
from fpdf import FPDF
import os

base = "/Users/dmichalk/dev/retail/sharepointdemo/sharepoint/seed-docs"
live = "/Users/dmichalk/dev/retail/sharepointdemo/sharepoint/livedemo-docs"

def make_inspection(path, store, inspector, date, itype, overall, findings):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(0, 12, itype.upper(), new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(4)
    pdf.set_font("Helvetica", "", 11)
    for line in [f"Location: {store}", f"Inspector: {inspector}", f"Date: {date}", f"Result: {overall}"]:
        pdf.cell(0, 7, line, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(6)
    pdf.set_font("Helvetica", "B", 13)
    pdf.cell(0, 8, "FINDINGS", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    for i, (sev, desc) in enumerate(findings, 1):
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 6, f"Finding {i} -- [{sev}]", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, desc)
        pdf.ln(3)
    pdf.set_font("Helvetica", "I", 9)
    pdf.cell(0, 5, "This report is confidential and intended for internal use only.", new_x="LMARGIN", new_y="NEXT")
    pdf.output(path)

def make_workorder(path, wo):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, "MAINTENANCE WORK ORDER", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(2)
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, f"{wo['wo']}  |  Priority: {wo['priority']}  |  Status: {wo['status']}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(4)
    for label, val in [("Location", wo["store"]), ("Date Opened", wo["opened"]), ("Date Closed", wo["closed"]),
                        ("Category", wo["category"]), ("Equipment", wo["equipment"]),
                        ("Reported By", wo["reported_by"]), ("Assigned To", wo["assigned_to"])]:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(40, 6, f"{label}:")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 6, val)
        pdf.ln(1)
    pdf.ln(4)
    for section, text in [("Problem Description", wo["description"]), ("Resolution", wo["resolution"]), ("Cost", wo["cost"])]:
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 7, section, new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, text)
        pdf.ln(3)
    pdf.output(path)

def make_incident(path, inc):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, "STORE INCIDENT REPORT", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(2)
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, f"Severity: {inc['severity']}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(4)
    for label, val in [("Location", inc["store"]), ("Date/Time", inc["date"]), ("Incident Type", inc["type"]),
                        ("Reported By", inc["reported_by"]), ("Persons Involved", inc["persons"])]:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(40, 6, f"{label}:")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 6, val)
        pdf.ln(1)
    pdf.ln(3)
    for section, text in [("Incident Description", inc["description"]), ("Immediate Actions Taken", inc["actions"]),
                           ("Root Cause", inc["root_cause"]), ("Corrective Actions", inc["corrective"])]:
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 7, section, new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, text)
        pdf.ln(3)
    pdf.output(path)

def make_planogram(path, p):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, "PLANOGRAM COMPLIANCE AUDIT", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(4)
    for label, val in [("Store", p["store"]), ("Auditor", p["auditor"]), ("Audit Date", p["date"]),
                        ("Department", p["department"]), ("Planogram", p["planogram"]), ("Overall Compliance", p["compliance"])]:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(40, 6, f"{label}:")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 6, val)
        pdf.ln(1)
    pdf.ln(4)
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "FINDINGS", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    for i, (status, desc) in enumerate(p["findings"], 1):
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 6, f"{i}. [{status}]", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, desc)
        pdf.ln(3)
    pdf.output(path)

# === INSPECTIONS ===
make_inspection(
    os.path.join(base, "Inspections", "food_safety_inspection_store_4421_2026-07-15.pdf"),
    "Store #4421 -- Maple Grove, MN", "Sarah Chen, Certified Food Safety Inspector",
    "July 15, 2026", "Food Safety & Sanitation Inspection", "CONDITIONAL PASS",
    [("Critical", "Walk-in cooler #2 operating at 44F -- exceeds 41F threshold. Three cases of deli meat measured at 43F internal temp. Corrective: Unit serviced same day by Refrigeration Solutions Inc. Temp verified at 38F by 4:30 PM."),
     ("Major", "Prep sink in bakery department lacks hot water supply. Measured at 87F; minimum required 110F. Water heater inspection scheduled for 7/17."),
     ("Minor", "Two ceiling tiles above produce wet rack show water staining. No active leak observed. Facilities notified."),
     ("Minor", "Employee handwash log for deli incomplete -- 3 of 7 shifts missing signatures week of 7/8."),
     ("Observation", "Excellent FIFO rotation observed in dairy cooler. All date labels current and legible.")])

make_inspection(
    os.path.join(base, "Inspections", "food_safety_inspection_store_5102_2026-07-22.pdf"),
    "Store #5102 -- Eden Prairie, MN", "Marcus Rivera, Certified Food Safety Inspector",
    "July 22, 2026", "Food Safety & Sanitation Inspection", "PASS",
    [("Minor", "Deli slicer #3 blade guard has minor chip on edge. Does not contact food surface but should be replaced at next maintenance cycle."),
     ("Minor", "Floor drain in meat processing room slow to clear. Cleared with enzyme treatment during inspection. Schedule preventive drain service."),
     ("Observation", "Excellent pest control documentation. Quarterly Terminix reports filed and current through Q2 FY26."),
     ("Observation", "All cold-hold units within spec. Lowest reading 33F (frozen), highest 39F (dairy reach-in).")])

make_inspection(
    os.path.join(base, "Inspections", "health_dept_inspection_store_3287_2026-08-05.pdf"),
    "Store #3287 -- Bloomington, MN", "Hennepin County Health Department -- Inspector J. Kowalski, Badge #1847",
    "August 5, 2026", "Routine Health Department Inspection", "SCORE: 91/100 -- PASS",
    [("Violation 3-501.16", "Hot-hold soup bar measured at 128F at 2:15 PM. Minimum 135F required. Two soup varieties discarded and replenished. Staff re-trained on hot-hold monitoring at shift change."),
     ("Violation 4-601.11", "Residue observed on interior surfaces of ice machine in bakery. Machine taken out of service, sanitized, and returned to operation at 3:40 PM."),
     ("Compliant", "All food handler permits current. 47 of 47 associates verified."),
     ("Compliant", "Chemical storage properly separated from food storage in all observed areas."),
     ("Compliant", "Allergen labeling on all prepared foods items verified accurate and legible.")])

print("3 inspections")

# === MAINTENANCE WORK ORDERS ===
make_workorder(os.path.join(base, "Maintenance", "wo_78432_refrigeration_store_4421_2026-07-15.pdf"), {
    "wo": "WO-78432", "store": "Store #4421 -- Maple Grove, MN", "opened": "July 15, 2026", "closed": "July 15, 2026",
    "priority": "EMERGENCY", "status": "CLOSED", "category": "Refrigeration",
    "equipment": "Walk-in Cooler #2 (Hussmann IRL-0608, Serial: HRL2019-44218)",
    "reported_by": "Sarah Chen (Food Safety Inspector -- triggered by inspection finding)",
    "assigned_to": "Refrigeration Solutions Inc. -- Tech: Dave Kowalski",
    "description": "Walk-in cooler #2 operating at 44F, exceeding 41F food safety threshold. Deli meat product measured at 43F internal. Immediate service required per food safety protocol.",
    "resolution": "Diagnosed failed evaporator fan motor (part #EFM-2247). Replaced on-site from service truck inventory. Verified unit cooling to 36F within 90 minutes. All product above 41F discarded per food safety SOP. Estimated product loss: $847.",
    "cost": "$1,247.00 (labor: $400, parts: $289, product loss: $847)"})

make_workorder(os.path.join(base, "Maintenance", "wo_78501_hvac_store_5102_2026-07-18.pdf"), {
    "wo": "WO-78501", "store": "Store #5102 -- Eden Prairie, MN", "opened": "July 18, 2026", "closed": "July 21, 2026",
    "priority": "HIGH", "status": "CLOSED -- follow-up scheduled September", "category": "HVAC",
    "equipment": "Rooftop Unit #3 (Carrier 48TM, Serial: CAR2021-99103) -- serves bakery/deli",
    "reported_by": "Tom Nguyen, Store Manager", "assigned_to": "Comfort Systems USA -- Tech: Maria Santos",
    "description": "Bakery area ambient temperature reached 82F at 1 PM. RTU #3 running but not cooling. Product quality concern for cake decorating and chocolate displays.",
    "resolution": "Found refrigerant charge low -- 4 lbs R-410A below spec. Located and repaired pinhole leak in condenser coil joint. Recharged system. Verified bakery ambient at 72F after 3 hours. Recommended condenser coil replacement at next scheduled maintenance window (September).",
    "cost": "$2,180.00 (labor: $960, parts: $120, refrigerant: $340, leak detection: $760)"})

make_workorder(os.path.join(base, "Maintenance", "wo_78623_plumbing_store_3287_2026-07-28.pdf"), {
    "wo": "WO-78623", "store": "Store #3287 -- Bloomington, MN", "opened": "July 28, 2026", "closed": "OPEN",
    "priority": "MEDIUM", "status": "OPEN", "category": "Plumbing",
    "equipment": "Bakery prep sink (Advance Tabco FC-3-1620, install date 2019)",
    "reported_by": "Health Dept Inspection finding -- hot water below minimum",
    "assigned_to": "Roto-Rooter Commercial -- awaiting scheduling",
    "description": "Hot water at bakery prep sink measured 87F. Minimum required 110F for handwash / equipment sanitation. Point-of-use water heater suspected. Flagged during health department inspection 8/5.",
    "resolution": "PENDING -- Vendor site visit scheduled for 8/8. Interim mitigation: portable hot water dispenser placed at station.",
    "cost": "TBD"})

print("3 work orders")

# === INCIDENTS ===
make_incident(os.path.join(base, "Incidents", "incident_store_4421_2026-07-20_slip_fall.pdf"), {
    "store": "Store #4421 -- Maple Grove, MN", "date": "July 20, 2026, 2:35 PM",
    "type": "Customer Slip & Fall", "reported_by": "Jessica Pham, Front End Supervisor",
    "persons": "Customer: Margaret Olsen (age ~65). Witness: Employee Carlos Mendez (badge #4421-087).",
    "severity": "MODERATE -- medical attention sought, no fracture",
    "description": "Customer slipped on wet floor near produce wet rack. Floor mat had shifted, exposing wet tile. Customer fell onto right side, complained of hip pain. Customer was alert and oriented. Declined ambulance but requested help to her vehicle.",
    "actions": "1) Area cordoned off immediately. 2) Wet floor signs placed. 3) Floor mat repositioned and secured. 4) Photos taken of area. 5) Customer provided incident form and store manager business card. 6) Customer's daughter called store at 4:15 PM -- customer went to Urgent Care, X-ray negative, diagnosed with bruised hip.",
    "root_cause": "Floor mat not properly secured with anti-slip backing. Produce wet rack misting cycle creates overspray that reaches aisle when mat is displaced. Mat replacement overdue -- current mat purchased 2023.",
    "corrective": "1) All produce area mats replaced with anti-slip backed mats (completed 7/21, cost $340). 2) Wet rack misting nozzles adjusted to reduce overspray. 3) Produce team briefed on hourly floor checks."})

make_incident(os.path.join(base, "Incidents", "incident_store_3287_2026-08-01_equipment.pdf"), {
    "store": "Store #3287 -- Bloomington, MN", "date": "August 1, 2026, 6:15 AM",
    "type": "Equipment Failure -- Power Outage", "reported_by": "Kevin Park, Opening Manager",
    "persons": "Store opening crew (4 associates). No injuries.",
    "severity": "LOW -- no product loss, no injuries, power restored within SLA",
    "description": "Main electrical panel tripped at approximately 5:50 AM, cutting power to refrigerated cases in grocery aisles 3-7 (dairy, frozen, beverages). Backup generator activated for walk-in coolers and freezers but does not cover floor cases. Power restored by Xcel Energy at 7:45 AM. Total outage: ~2 hours.",
    "actions": "1) Verified backup generator running for walk-ins -- all walk-in temps held. 2) Spot-checked frozen case temps at 6:15 AM: -2F to 8F (acceptable). 3) Dairy reach-in temps: 38F to 44F -- borderline. 4) Placed do-not-stock holds on dairy cases until temps recovered. 5) Called Xcel Energy at 6:00 AM. 6) Temps verified recovered by 9:00 AM.",
    "root_cause": "Xcel Energy transformer failure on distribution line. Not within store control. However, backup generator scope does not include floor-level refrigerated cases -- known gap in emergency power plan.",
    "corrective": "1) Filed claim with Xcel Energy. 2) Submitted capital request for expanded generator capacity ($18,000 estimate). 3) Updated store emergency SOP to include temp monitoring checklist for power events."})

print("2 incidents")

# === PLANOGRAMS ===
make_planogram(os.path.join(base, "Planograms", "planogram_audit_store_4421_cereal_2026-07-25.pdf"), {
    "store": "Store #4421 -- Maple Grove, MN", "auditor": "Regional Merchandising -- Lisa Tran",
    "date": "July 25, 2026", "department": "Grocery -- Cereal Aisle (Aisle 6)",
    "planogram": "PLN-2026-Q3-CRL-v2 (effective 7/1/2026)", "compliance": "78%",
    "findings": [
        ("NON-COMPLIANT", "Shelf 3, Position 4-6: Store brand granola placed in position allocated to General Mills Nature Valley. Lost premium placement revenue estimated $120/week."),
        ("NON-COMPLIANT", "End cap facing: Kellogg's promotional display (Back-to-School) not built. Display shipper received 7/10 but still in backroom. Vendor promotional credit at risk: $500."),
        ("NON-COMPLIANT", "Shelf 5 (bottom): 4 facings of discontinued Malt-O-Meal Berry Colossal Crunch still on shelf. Product delisted effective 6/15. No shelf tag."),
        ("COMPLIANT", "Top shelf power wing correctly merchandised with Quaker Oats seasonal oatmeal packets. Price point $4.99 verified."),
        ("COMPLIANT", "Shelf 1-2 brand blocking (General Mills family) correct. Facings match planogram. Price accuracy 100%."),
        ("OBSERVATION", "Overall aisle cleanliness good. No damaged packages. Shelf labels clean and current except for the delisted item.")]})

make_planogram(os.path.join(base, "Planograms", "planogram_audit_store_5102_frozen_2026-08-02.pdf"), {
    "store": "Store #5102 -- Eden Prairie, MN", "auditor": "Regional Merchandising -- Lisa Tran",
    "date": "August 2, 2026", "department": "Frozen Foods -- Pizza / Snacks (Doors 14-18)",
    "planogram": "PLN-2026-Q3-FZP-v1 (effective 7/1/2026)", "compliance": "92%",
    "findings": [
        ("NON-COMPLIANT", "Door 16, shelf 2: DiGiorno Rising Crust Pepperoni allocated 3 facings, only 1 on shelf. Adjacent Tombstone overfaced into the gap. Backroom check found 2 cases -- restocked during audit."),
        ("COMPLIANT", "All Totino's Party Pizza facings correct (8 facings across 2 shelves). Price labels accurate."),
        ("COMPLIANT", "Hot Pockets / Lean Pockets section properly blocked by brand. New Lean Pockets Chicken Jalapeno SKU added per planogram update."),
        ("COMPLIANT", "Frozen snacks end cap (Door 14) correctly merchandised with Bagel Bites promotional display. Ad price $3.99 verified."),
        ("OBSERVATION", "Door 17 gasket showing wear -- slight condensation inside. Not affecting product but should be flagged for preventive maintenance.")]})

print("2 planograms")

# === LIVE DEMO DOCS ===
make_inspection(
    os.path.join(live, "Inspections", "food_safety_inspection_store_4421_2026-08-12.pdf"),
    "Store #4421 -- Maple Grove, MN", "Sarah Chen, Certified Food Safety Inspector",
    "August 12, 2026", "Food Safety & Sanitation Inspection", "PASS",
    [("Minor", "Walk-in cooler #2 (repaired 7/15) operating at 37F -- well within spec. Repair verified effective."),
     ("Minor", "Bakery prep sink hot water now measuring 122F -- compliant after water heater replacement (WO-78623)."),
     ("Observation", "All corrective actions from 7/15 inspection verified complete. Handwash logs current and complete across all departments."),
     ("Observation", "New produce area floor mats with anti-slip backing in place. No wet floor conditions observed during 45-minute walkthrough.")])

make_incident(os.path.join(live, "Incidents", "incident_store_4421_2026-08-14_refrigeration.pdf"), {
    "store": "Store #4421 -- Maple Grove, MN", "date": "August 14, 2026, 11:30 PM",
    "type": "Refrigeration Failure -- Frozen Cases", "reported_by": "Night Crew Lead -- Alex Kim",
    "persons": "Night stocking crew (6 associates). No injuries.",
    "severity": "HIGH -- refrigeration failure with $3,200 product loss",
    "description": "Frozen food cases in aisle 8 (doors 20-24) found at 28F during overnight stocking at 11:30 PM. Product partially thawed. Compressor rack #2 alarming -- high discharge pressure fault. Estimated 200+ units of frozen product affected across ice cream, frozen vegetables, and frozen meals.",
    "actions": "1) All affected product pulled and staged in walk-in freezer. 2) Emergency maintenance call placed at 11:45 PM. 3) Cases powered down to prevent compressor damage. 4) Product temp log started every 30 min. 5) Store manager notified at 11:50 PM.",
    "root_cause": "Condenser fan motor failure on compressor rack #2 caused high head pressure and thermal overload. Fan motor bearings seized. Same rack services frozen cases 20-24 and backup unit was offline for scheduled maintenance.",
    "corrective": "1) Emergency fan motor replacement completed at 3:15 AM 8/15. 2) Cases restored to -5F by 6:00 AM. 3) $3,200 in frozen product discarded. 4) Backup unit maintenance expedited. 5) Facilities to review PM schedule -- two refrigeration failures in 30 days at store #4421."})

print("2 live demo docs")
print("\nDone! All store ops documents generated.")
