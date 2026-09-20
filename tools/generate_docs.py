#!/usr/bin/env python3
"""Generate ~100 realistic retail store ops PDFs for the SharePoint Openflow demo.

12 stores, 6 months of data, 4 document types. Each document has enough
detail for AI_EXTRACT to pull structured fields and for Cortex Search to
return meaningful results on natural language queries.

Usage: python3 tools/generate_docs.py
"""
from fpdf import FPDF
import os
import random
import shutil
from datetime import datetime, timedelta

random.seed(42)

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sharepoint", "seed-docs")
live = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sharepoint", "livedemo-docs")

STORES = [
    ("#3287", "Bloomington, MN"),
    ("#4421", "Maple Grove, MN"),
    ("#4590", "Plymouth, MN"),
    ("#5102", "Eden Prairie, MN"),
    ("#5234", "Minnetonka, MN"),
    ("#5501", "Woodbury, MN"),
    ("#6010", "Eagan, MN"),
    ("#6223", "Burnsville, MN"),
    ("#7101", "Lakeville, MN"),
    ("#7345", "Apple Valley, MN"),
    ("#8002", "Roseville, MN"),
    ("#8419", "Brooklyn Park, MN"),
]

INSPECTORS = [
    "Sarah Chen, Certified Food Safety Inspector",
    "Marcus Rivera, Certified Food Safety Inspector",
    "Jennifer Walsh, Senior Safety Auditor",
    "David Kim, Health Department Inspector",
    "Lisa Tran, Regional Compliance Officer",
]

MERCH_AUDITORS = [
    "Regional Merchandising -- Lisa Tran",
    "Regional Merchandising -- Kevin Park",
    "District Merchandising -- Maria Santos",
]

MAINTENANCE_VENDORS = {
    "Refrigeration": ["Refrigeration Solutions Inc.", "CoolTech Services", "Arctic Mechanical"],
    "HVAC": ["Comfort Systems USA", "Trane Commercial", "Johnson Controls"],
    "Plumbing": ["Roto-Rooter Commercial", "Citywide Plumbing", "Pipeworks LLC"],
    "Electrical": ["Midwest Electric", "PowerPro Services", "Bright Spark Electric"],
}

EQUIPMENT_BY_CATEGORY = {
    "Refrigeration": [
        "Walk-in Cooler #1 (Hussmann IRL-0608)", "Walk-in Cooler #2 (Hussmann IRL-0608)",
        "Walk-in Freezer (Kolpak QSX7-0806)", "Dairy Reach-in (True GDM-49F)",
        "Frozen Cases Doors 14-18 (Hillphoenix GNFM)", "Meat Case (Tyler NLM)",
        "Compressor Rack #1", "Compressor Rack #2",
    ],
    "HVAC": [
        "Rooftop Unit #1 (Carrier 48TM) -- serves front of store",
        "Rooftop Unit #2 (Carrier 48TM) -- serves grocery aisles",
        "Rooftop Unit #3 (Carrier 48TM) -- serves bakery/deli",
        "Exhaust Fan -- bakery oven hood",
    ],
    "Plumbing": [
        "Bakery prep sink (Advance Tabco FC-3-1620)",
        "Deli handwash station", "Restroom fixtures -- customer",
        "Floor drain -- meat processing room", "Grease trap -- deli",
    ],
    "Electrical": [
        "Main electrical panel", "Emergency lighting -- exit signs aisle 4-6",
        "POS register #3", "Bakery oven circuit breaker",
        "Parking lot light pole #7",
    ],
}

INSPECTION_FINDINGS_POOL = [
    ("Critical", "Walk-in cooler operating at {temp}F -- exceeds 41F threshold. Product measured at {ptemp}F internal.", "Unit serviced same day. Temp verified at 38F within 2 hours."),
    ("Critical", "Raw chicken stored above ready-to-eat items in walk-in cooler. Cross-contamination risk.", "Items immediately repositioned. Staff re-trained on storage order protocol."),
    ("Major", "Prep sink in {dept} department lacks hot water supply. Measured at {temp}F; minimum required 110F.", "Water heater inspection scheduled within 48 hours."),
    ("Major", "Hot-hold soup bar measured at {temp}F. Minimum 135F required.", "Soup varieties discarded and replenished. Staff re-trained on hot-hold monitoring."),
    ("Major", "Deli slicer blade guard has visible damage. Potential metal contamination risk.", "Slicer taken out of service immediately. Replacement part ordered."),
    ("Minor", "Ceiling tiles above produce wet rack show water staining. No active leak observed.", "Facilities notified for inspection."),
    ("Minor", "Employee handwash log incomplete -- {n} of 7 shifts missing signatures.", "Department manager counseled. Logs now reviewed at each shift change."),
    ("Minor", "Floor drain slow to clear in meat processing room.", "Cleared with enzyme treatment during inspection. Preventive service scheduled."),
    ("Minor", "Deli display case glass cracked -- cosmetic only, no food contact.", "Replacement glass ordered. Expected within 5 business days."),
    ("Minor", "Expired product found on shelf -- {n} items past sell-by date in {dept}.", "Items pulled immediately. Rotation audit conducted for entire department."),
    ("Observation", "Excellent FIFO rotation observed in dairy cooler. All date labels current and legible.", ""),
    ("Observation", "All cold-hold units within spec. Lowest reading {temp}F, highest {htemp}F.", ""),
    ("Observation", "Excellent pest control documentation. Quarterly reports filed and current.", ""),
    ("Observation", "Chemical storage properly separated from food storage in all observed areas.", ""),
    ("Compliant", "All food handler permits current. {n} of {n} associates verified.", ""),
    ("Compliant", "Allergen labeling on all prepared foods items verified accurate and legible.", ""),
]

INCIDENT_TYPES = [
    {
        "type": "Customer Slip & Fall",
        "severity": "MODERATE",
        "desc": "Customer slipped on {cause} near {location}. Customer complained of {injury}. {outcome}.",
        "root": "{cause_detail}. {contributing}.",
        "corrective": "1) Area secured immediately. 2) {fix1}. 3) {fix2}. 4) Incident documented with photos.",
        "cost": "${cost}",
    },
    {
        "type": "Equipment Failure -- Refrigeration",
        "severity": "HIGH",
        "desc": "Frozen food cases {doors} found at {temp}F during {shift}. Product partially thawed. {compressor} alarming -- {fault}.",
        "root": "{motor_issue}. Same rack services {doors} and backup unit was offline for scheduled maintenance.",
        "corrective": "1) All affected product pulled to walk-in freezer. 2) Emergency maintenance call placed. 3) ${cost} in product discarded. 4) PM schedule under review.",
        "cost": "${cost}",
    },
    {
        "type": "Equipment Failure -- Power Outage",
        "severity": "LOW",
        "desc": "Power outage affecting {area}. Backup generator activated for walk-ins. Floor cases on utility power lost cooling for {duration}.",
        "root": "Utility transformer failure. Not within store control. Backup generator scope does not include floor-level cases.",
        "corrective": "1) Filed claim with utility provider. 2) Capital request submitted for expanded generator capacity. 3) Emergency SOP updated.",
        "cost": "TBD",
    },
    {
        "type": "Theft -- Shoplifting",
        "severity": "LOW",
        "desc": "Loss prevention observed individual concealing {items} in {method}. Subject exited store without payment. {apprehended}.",
        "root": "Blind spot in camera coverage near {location}. Subject exploited gap during peak traffic.",
        "corrective": "1) Police report filed (case #{case}). 2) Camera angle adjusted. 3) Staff briefed on awareness protocol.",
        "cost": "${cost} estimated product loss",
    },
    {
        "type": "Employee Injury -- Lifting",
        "severity": "MODERATE",
        "desc": "Associate {name} reported {injury} while {activity} in {dept}. {treatment}.",
        "root": "Pallet weight exceeded single-person lift limit. No spotter present.",
        "corrective": "1) Workers comp claim filed. 2) Two-person lift policy reinforced. 3) Department briefed at next shift meeting.",
        "cost": "Workers comp claim pending",
    },
]

PLANO_DEPARTMENTS = [
    ("Grocery -- Cereal Aisle (Aisle 6)", "PLN-2026-Q3-CRL-v2"),
    ("Grocery -- Snacks (Aisle 8)", "PLN-2026-Q3-SNK-v1"),
    ("Frozen Foods -- Pizza / Snacks (Doors 14-18)", "PLN-2026-Q3-FZP-v1"),
    ("Frozen Foods -- Ice Cream (Doors 19-22)", "PLN-2026-Q3-ICE-v1"),
    ("Dairy -- Yogurt / Milk (Doors 1-6)", "PLN-2026-Q3-DRY-v2"),
    ("Beverage -- Soda / Water (Aisle 10)", "PLN-2026-Q3-BEV-v1"),
    ("Health & Beauty (Aisle 12-13)", "PLN-2026-Q3-HBA-v1"),
    ("Pet Food (Aisle 15)", "PLN-2026-Q3-PET-v1"),
]

PLANO_FINDINGS_POOL = [
    ("NON-COMPLIANT", "Shelf {shelf}, Position {pos}: Store brand product placed in position allocated to {brand}. Lost premium placement revenue estimated ${rev}/week."),
    ("NON-COMPLIANT", "End cap facing: {brand} promotional display not built. Display shipper received but still in backroom. Vendor promotional credit at risk: ${rev}."),
    ("NON-COMPLIANT", "{n} facings of discontinued {product} still on shelf. Product delisted effective {date}. No shelf tag."),
    ("NON-COMPLIANT", "{brand} allocated {n} facings, only {actual} on shelf. Adjacent {other} overfaced into the gap. Backroom check found {cases} cases -- restocked during audit."),
    ("COMPLIANT", "All {brand} facings correct ({n} facings across {shelves} shelves). Price labels accurate."),
    ("COMPLIANT", "Brand blocking correct for {brand} family. Facings match planogram. Price accuracy 100%."),
    ("COMPLIANT", "End cap correctly merchandised with {brand} promotional display. Ad price ${price} verified."),
    ("OBSERVATION", "Overall aisle cleanliness good. No damaged packages. Shelf labels clean and current."),
    ("OBSERVATION", "Door {door} gasket showing wear -- slight condensation inside. Flag for preventive maintenance."),
    ("OBSERVATION", "Shelf tag font size below standard on {n} tags. Readable but should be reprinted at next reset."),
]

BRANDS = ["General Mills", "Kellogg's", "Frito-Lay", "Coca-Cola", "Pepsi", "Nestle", "Kraft Heinz",
           "Procter & Gamble", "Unilever", "Mars", "Mondelez", "ConAgra", "Quaker Oats",
           "DiGiorno", "Totino's", "Bagel Bites", "Hot Pockets", "Ben & Jerry's", "Haagen-Dazs"]

# ---- PDF helpers ----
def make_pdf():
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()
    return pdf

def pdf_title(pdf, title):
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(3)

def pdf_field(pdf, label, value):
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, 6, f"{label}: {value}", new_x="LMARGIN", new_y="NEXT")

def pdf_section(pdf, title, text):
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, title, new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.multi_cell(0, 5, str(text))
    pdf.ln(3)

def random_date(start_month=3, end_month=8, year=2026):
    m = random.randint(start_month, end_month)
    d = random.randint(1, 28)
    return datetime(year, m, d)

def fmt_date(dt):
    return dt.strftime("%B %d, %Y")

# ---- Generators ----
def gen_inspection(store_id, store_loc, dt):
    pdf = make_pdf()
    itype = random.choice(["Food Safety & Sanitation Inspection", "Routine Health Department Inspection"])
    inspector = random.choice(INSPECTORS)
    n_findings = random.randint(3, 6)
    findings = random.sample(INSPECTION_FINDINGS_POOL, min(n_findings, len(INSPECTION_FINDINGS_POOL)))
    
    overall = random.choice(["PASS", "PASS", "PASS", "CONDITIONAL PASS", "SCORE: {}/100 -- PASS".format(random.randint(85, 98))])
    
    pdf_title(pdf, itype.upper())
    pdf_field(pdf, "Location", f"Store {store_id} -- {store_loc}")
    pdf_field(pdf, "Inspector", inspector)
    pdf_field(pdf, "Date", fmt_date(dt))
    pdf_field(pdf, "Result", overall)
    pdf.ln(4)
    
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "FINDINGS", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    
    depts = ["bakery", "deli", "produce", "dairy", "meat"]
    for i, (sev, desc, action) in enumerate(findings, 1):
        if pdf.get_y() > 250:
            pdf.add_page()
        desc = desc.format(
            temp=random.randint(42, 48) if "temp" in desc else "",
            ptemp=random.randint(42, 46),
            htemp=random.randint(38, 41),
            dept=random.choice(depts),
            n=random.randint(2, 5),
        )
        action = action if action else ""
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 6, f"Finding {i} -- [{sev}]", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, desc)
        if action:
            if pdf.get_y() > 260:
                pdf.add_page()
            pdf.set_x(pdf.l_margin)
            pdf.set_font("Helvetica", "", 9)
            pdf.multi_cell(0, 5, f"Corrective: {action}")
        pdf.ln(2)
    
    fname = f"inspection_{store_id.replace('#','')}_{'food_safety' if 'Food' in itype else 'health_dept'}_{dt.strftime('%Y-%m-%d')}.pdf"
    pdf.output(os.path.join(base, "Inspections", fname))
    return fname

def gen_maintenance(store_id, store_loc, dt):
    pdf = make_pdf()
    cat = random.choice(list(MAINTENANCE_VENDORS.keys()))
    vendor = random.choice(MAINTENANCE_VENDORS[cat])
    equip = random.choice(EQUIPMENT_BY_CATEGORY[cat])
    priority = random.choice(["EMERGENCY", "HIGH", "HIGH", "MEDIUM", "MEDIUM", "LOW"])
    wo_num = f"WO-{random.randint(78000, 79999)}"
    is_open = random.random() < 0.25
    
    problems = {
        "Refrigeration": [
            f"Unit operating at {random.randint(42,50)}F, exceeding 41F food safety threshold.",
            "Compressor cycling rapidly. High head pressure fault on display.",
            "Evaporator coil icing over. Defrost cycle not activating.",
            "Condenser fan motor failure. Unit running but not cooling.",
        ],
        "HVAC": [
            f"Area ambient temperature reached {random.randint(78,88)}F. RTU running but not cooling.",
            "Unusual noise from rooftop unit. Vibration felt in ceiling tiles below.",
            "Thermostat unresponsive. Cannot adjust temperature.",
            "Exhaust fan belt snapped. Smoke smell in bakery.",
        ],
        "Plumbing": [
            f"Hot water at prep sink measured {random.randint(75,95)}F. Minimum required 110F.",
            "Floor drain backing up during wash-down. Standing water in prep area.",
            "Grease trap overflowing. Odor complaint from customers.",
            "Toilet running continuously in customer restroom.",
        ],
        "Electrical": [
            "Intermittent power flickering in aisle 4-6. Lights and refrigerated cases affected.",
            "Emergency exit sign dark. Battery backup not charging.",
            "POS register rebooting randomly. Possible power supply issue.",
            "Parking lot light pole out. Safety concern for closing crew.",
        ],
    }
    
    resolutions = {
        True: "PENDING -- Vendor site visit scheduled. Interim mitigation in place.",
        False: "Diagnosed and repaired on-site. Verified operational.",
    }
    
    problem = random.choice(problems[cat])
    cost = f"${random.randint(200, 4500):.2f}" if not is_open else "TBD"
    close_date = "OPEN" if is_open else fmt_date(dt + timedelta(days=random.randint(0, 3)))
    
    pdf_title(pdf, "MAINTENANCE WORK ORDER")
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, f"{wo_num}  |  Priority: {priority}  |  Status: {'OPEN' if is_open else 'CLOSED'}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(3)
    
    pdf_field(pdf, "Location", f"Store {store_id} -- {store_loc}")
    pdf_field(pdf, "Date Opened", fmt_date(dt))
    pdf_field(pdf, "Date Closed", close_date)
    pdf_field(pdf, "Category", cat)
    pdf_field(pdf, "Equipment", equip)
    pdf_field(pdf, "Assigned To", f"{vendor} -- Tech: {random.choice(['Dave K.','Maria S.','Tom N.','Alex R.','Chris L.'])}")
    pdf.ln(3)
    pdf_section(pdf, "Problem Description", problem)
    pdf_section(pdf, "Resolution", resolutions[is_open])
    pdf_section(pdf, "Cost", cost)
    
    fname = f"wo_{wo_num.replace('WO-','')}_{cat.lower()}_{store_id.replace('#','')}_{dt.strftime('%Y-%m-%d')}.pdf"
    pdf.output(os.path.join(base, "Maintenance", fname))
    return fname

def gen_incident(store_id, store_loc, dt):
    pdf = make_pdf()
    template = random.choice(INCIDENT_TYPES)
    
    causes = ["wet floor near produce wet rack", "spilled liquid in beverage aisle", "ice buildup near frozen cases",
              "loose floor mat at entrance", "recently mopped floor in deli"]
    locations = ["produce section", "beverage aisle", "frozen food aisle", "front entrance", "deli counter area"]
    injuries = ["hip pain", "wrist pain", "knee pain", "back pain", "shoulder pain"]
    
    desc = template["desc"].format(
        cause=random.choice(causes), location=random.choice(locations),
        injury=random.choice(injuries), outcome="Customer declined ambulance. Provided incident form.",
        doors=f"doors {random.randint(14,22)}-{random.randint(23,28)}",
        temp=random.randint(22, 32), shift=random.choice(["overnight stocking", "morning prep", "afternoon peak"]),
        compressor=f"Compressor rack #{random.randint(1,3)}", fault="high discharge pressure fault",
        area=f"aisles {random.randint(1,5)}-{random.randint(6,10)}", duration=f"{random.randint(1,4)} hours",
        items=random.choice(["cosmetics", "electronics", "meat products", "spirits"]),
        method=random.choice(["a bag", "clothing", "a backpack"]),
        apprehended=random.choice(["Subject not apprehended.", "Subject detained by LP until police arrival."]),
        name=random.choice(["J. Martinez", "K. Johnson", "R. Patel", "S. Williams"]),
        activity=random.choice(["stacking cases", "lifting pallet", "unloading truck"]),
        dept=random.choice(["grocery backroom", "dairy cooler", "receiving dock"]),
        treatment=random.choice(["Ice applied. Associate returned to light duty.", "Sent to urgent care for evaluation."]),
        case=random.randint(20260001, 20269999),
        motor_issue="Condenser fan motor failure caused high head pressure and thermal overload",
        cost=random.randint(200, 5000),
    )
    root = template["root"].format(
        cause_detail=random.choice(["Floor mat not properly secured", "Spill not cleaned within 5-minute SOP", "Misting nozzle overspray"]),
        contributing=random.choice(["Mat replacement overdue", "Hourly floor checks not completed", "Wet floor sign not placed"]),
        motor_issue="Condenser fan motor failure", doors=f"doors {random.randint(14,22)}-{random.randint(23,28)}",
        location=random.choice(["self-checkout area", "cosmetics aisle", "entrance vestibule"]),
        case=random.randint(20260001, 20269999),
    )
    corrective = template["corrective"].format(
        fix1=random.choice(["Floor mats replaced with anti-slip backed mats", "Spill cleanup SOP re-trained", "Camera coverage expanded"]),
        fix2=random.choice(["Hourly floor checks added to shift checklist", "Wet floor sign inventory increased", "LP staffing adjusted for peak hours"]),
        cost=random.randint(200, 5000), case=random.randint(20260001, 20269999),
    )
    
    pdf_title(pdf, "STORE INCIDENT REPORT")
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, f"Severity: {template['severity']}", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(3)
    
    pdf_field(pdf, "Location", f"Store {store_id} -- {store_loc}")
    pdf_field(pdf, "Date/Time", f"{fmt_date(dt)}, {random.randint(6,22)}:{random.choice(['00','15','30','45'])} {'AM' if random.random() < 0.4 else 'PM'}")
    pdf_field(pdf, "Incident Type", template["type"])
    pdf_field(pdf, "Reported By", random.choice(["Front End Supervisor", "Night Crew Lead", "Store Manager", "Loss Prevention Associate", "Department Manager"]))
    pdf.ln(3)
    pdf_section(pdf, "Incident Description", desc)
    pdf_section(pdf, "Root Cause", root)
    pdf_section(pdf, "Corrective Actions", corrective)
    
    safe_type = template["type"].split(" -- ")[0].lower().replace(" ", "_").replace("&", "and")
    fname = f"incident_{store_id.replace('#','')}_{dt.strftime('%Y-%m-%d')}_{safe_type}.pdf"
    pdf.output(os.path.join(base, "Incidents", fname))
    return fname

def gen_planogram(store_id, store_loc, dt):
    pdf = make_pdf()
    dept, plano_id = random.choice(PLANO_DEPARTMENTS)
    auditor = random.choice(MERCH_AUDITORS)
    compliance = random.randint(65, 98)
    n_findings = random.randint(4, 7)
    findings = random.choices(PLANO_FINDINGS_POOL, k=n_findings)
    
    pdf_title(pdf, "PLANOGRAM COMPLIANCE AUDIT")
    pdf_field(pdf, "Store", f"Store {store_id} -- {store_loc}")
    pdf_field(pdf, "Auditor", auditor)
    pdf_field(pdf, "Audit Date", fmt_date(dt))
    pdf_field(pdf, "Department", dept)
    pdf_field(pdf, "Planogram", plano_id)
    pdf_field(pdf, "Compliance", f"{compliance}%")
    pdf.ln(4)
    
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "FINDINGS", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    
    for i, (status, desc_tmpl) in enumerate(findings, 1):
        if pdf.get_y() > 250:
            pdf.add_page()
        desc = desc_tmpl.format(
            shelf=random.randint(1, 5), pos=f"{random.randint(1,8)}-{random.randint(9,12)}",
            brand=random.choice(BRANDS), rev=random.randint(80, 500),
            n=random.randint(2, 6), actual=random.randint(1, 2),
            other=random.choice(BRANDS), cases=random.randint(1, 4),
            product=f"{random.choice(BRANDS)} {random.choice(['Variety Pack','Family Size','Original','Lite'])}",
            date=f"{random.randint(1,6)}/15", shelves=random.randint(1, 3),
            price=f"{random.randint(2,8)}.{random.choice(['49','99','79','29'])}",
            door=random.randint(14, 22),
        )
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 6, f"{i}. [{status}]", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, desc)
        pdf.ln(2)
    
    safe_dept = dept.split(" -- ")[0].lower().replace(" ", "_").replace("&", "and")
    fname = f"planogram_{store_id.replace('#','')}_{safe_dept}_{dt.strftime('%Y-%m-%d')}.pdf"
    pdf.output(os.path.join(base, "Planograms", fname))
    return fname

# ---- Main ----
def main():
    # Clean and recreate
    for folder in ["Inspections", "Maintenance", "Incidents", "Planograms"]:
        path = os.path.join(base, folder)
        if os.path.exists(path):
            shutil.rmtree(path)
        os.makedirs(path, exist_ok=True)
    
    for folder in ["Inspections", "Incidents"]:
        path = os.path.join(live, folder)
        if os.path.exists(path):
            shutil.rmtree(path)
        os.makedirs(path, exist_ok=True)

    counts = {"Inspections": 0, "Maintenance": 0, "Incidents": 0, "Planograms": 0}
    
    for store_id, store_loc in STORES:
        # Each store gets 2-3 inspections over 6 months
        for _ in range(random.randint(2, 3)):
            dt = random_date()
            gen_inspection(store_id, store_loc, dt)
            counts["Inspections"] += 1
        
        # Each store gets 2-4 maintenance work orders
        for _ in range(random.randint(2, 4)):
            dt = random_date()
            gen_maintenance(store_id, store_loc, dt)
            counts["Maintenance"] += 1
        
        # Each store gets 0-2 incidents (not every store has incidents)
        for _ in range(random.randint(0, 2)):
            dt = random_date()
            gen_incident(store_id, store_loc, dt)
            counts["Incidents"] += 1
        
        # Each store gets 1-2 planogram audits
        for _ in range(random.randint(1, 2)):
            dt = random_date()
            gen_planogram(store_id, store_loc, dt)
            counts["Planograms"] += 1

    # Live demo docs -- follow-up inspection for store #4421
    pdf = make_pdf()
    pdf_title(pdf, "FOOD SAFETY & SANITATION INSPECTION")
    pdf_field(pdf, "Location", "Store #4421 -- Maple Grove, MN")
    pdf_field(pdf, "Inspector", "Sarah Chen, Certified Food Safety Inspector")
    pdf_field(pdf, "Date", "September 15, 2026")
    pdf_field(pdf, "Result", "PASS")
    pdf.ln(4)
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "FINDINGS", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    for i, (sev, desc) in enumerate([
        ("Minor", "Walk-in cooler #2 operating at 37F -- well within spec. Previous repair verified effective."),
        ("Minor", "Bakery prep sink hot water now measuring 122F -- compliant after water heater replacement."),
        ("Observation", "All corrective actions from previous inspection verified complete."),
        ("Observation", "New produce area floor mats with anti-slip backing in place. No wet conditions observed."),
    ], 1):
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 6, f"Finding {i} -- [{sev}]", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 5, desc)
        pdf.ln(2)
    pdf.output(os.path.join(live, "Inspections", "inspection_4421_food_safety_2026-09-15.pdf"))

    # Live demo -- refrigeration incident for store #4421
    pdf = make_pdf()
    pdf_title(pdf, "STORE INCIDENT REPORT")
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, "Severity: HIGH -- refrigeration failure with $3,200 product loss", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(3)
    pdf_field(pdf, "Location", "Store #4421 -- Maple Grove, MN")
    pdf_field(pdf, "Date/Time", "September 18, 2026, 11:30 PM")
    pdf_field(pdf, "Incident Type", "Equipment Failure -- Refrigeration")
    pdf_field(pdf, "Reported By", "Night Crew Lead -- Alex Kim")
    pdf.ln(3)
    pdf_section(pdf, "Incident Description", "Frozen food cases doors 20-24 found at 28F during overnight stocking. Product partially thawed. Compressor rack #2 alarming -- high discharge pressure fault. 200+ units of frozen product affected.")
    pdf_section(pdf, "Root Cause", "Condenser fan motor failure on compressor rack #2. Fan motor bearings seized. Backup unit offline for scheduled maintenance.")
    pdf_section(pdf, "Corrective Actions", "1) Emergency fan motor replacement completed at 3:15 AM. 2) Cases restored to -5F by 6:00 AM. 3) $3,200 in product discarded. 4) PM schedule under review -- two refrigeration failures in 30 days at this store.")
    pdf.output(os.path.join(live, "Incidents", "incident_4421_2026-09-18_equipment_failure.pdf"))

    total = sum(counts.values())
    print(f"Generated {total} seed documents:")
    for k, v in counts.items():
        print(f"  {k}: {v}")
    print(f"\nGenerated 2 live demo documents")
    print(f"\nTotal: {total + 2}")

if __name__ == "__main__":
    main()
