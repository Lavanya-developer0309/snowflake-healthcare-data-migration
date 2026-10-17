"""
Synthetic US healthcare payer source-data generator
====================================================

Creates pipe-delimited "legacy payer" extract files that mimic what a client
sends for a Facets conversion:

    SRC_GROUP.txt         employer groups
    SRC_MEMBER.txt        subscribers + dependents with coverage
    SRC_PROVIDER.txt      individual / organisation providers
    SRC_CLAIM_HEADER.txt  medical claim headers
    SRC_CLAIM_LINE.txt    medical claim service lines

ALL DATA IS FAKE. No real people, members, providers or PHI are used.

The generator deliberately injects data-quality problems (bad dates, invalid
characters, duplicates, orphans, unmapped codes ...) so that the profiling,
transformation-reject and validation steps of the pipeline have something
real to catch. A summary of what was injected is written to
_injected_issues.json so you can prove the pipeline caught every one.

Uses only the Python standard library, so no pip install is needed.

Usage:
    python scripts/generate_source_data.py                       # BATCH_001, default sizes
    python scripts/generate_source_data.py --batch BATCH_002 --seed 7
"""

import argparse
import json
import os
import random
from datetime import date, timedelta

# --------------------------------------------------------------------------
# Reference lists
# --------------------------------------------------------------------------
FIRST_NAMES_M = ["James", "John", "Robert", "Michael", "William", "David", "Richard",
                 "Joseph", "Thomas", "Charles", "Daniel", "Matthew", "Anthony", "Mark",
                 "Steven", "Andrew", "Joshua", "Kevin", "Brian", "George", "Ryan", "Jacob"]
FIRST_NAMES_F = ["Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan",
                 "Jessica", "Sarah", "Karen", "Lisa", "Nancy", "Sandra", "Ashley", "Emily",
                 "Donna", "Michelle", "Carol", "Amanda", "Melissa", "Laura", "Olivia"]
LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
              "Rodriguez", "Martinez", "Hernandez", "Lopez", "Wilson", "Anderson", "Thomas",
              "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
              "Harris", "Clark", "Lewis", "Robinson", "Walker", "Young", "Allen", "King"]
CITIES = [("Dallas", "TX", "752"), ("Houston", "TX", "770"), ("Phoenix", "AZ", "850"),
          ("Atlanta", "GA", "303"), ("Chicago", "IL", "606"), ("Columbus", "OH", "432"),
          ("Charlotte", "NC", "282"), ("Denver", "CO", "802"), ("Nashville", "TN", "372"),
          ("Tampa", "FL", "336"), ("Richmond", "VA", "232"), ("Newark", "NJ", "071"),
          ("Seattle", "WA", "981"), ("Boston", "MA", "021"), ("Detroit", "MI", "482")]
STREETS = ["Main St", "Oak Ave", "Maple Dr", "Cedar Ln", "Park Blvd", "Elm St",
           "Lakeview Rd", "Hillcrest Ave", "Sunset Blvd", "River Rd", "Pine St"]
COMPANY_WORDS = ["Acme", "Summit", "Pioneer", "Blue Ridge", "Lone Star", "Harbor",
                 "Evergreen", "Granite", "Liberty", "Northwind", "Riverbend", "Keystone"]
COMPANY_TYPES = ["Manufacturing", "Logistics", "Foods", "Health Partners", "Tech Inc",
                 "Construction", "Retail Group", "School District", "Energy LLC"]

LOB_PLANS = {           # line of business -> legacy plan codes
    "COM": ["P100", "P200", "P300"],
    "MCR": ["M100", "M200"],
    "MCD": ["D100"],
}
SPECIALTIES = ["207Q00000X", "207R00000X", "208D00000X", "207X00000X", "2084P0800X",
               "207V00000X", "208000000X", "282N00000X", "261QU0200X"]
PROC_CODES = ["99213", "99214", "99203", "99204", "36415", "80053", "85025", "71046",
              "93000", "90471", "97110", "99283", "J1100", "G0439"]
DIAG_CODES = ["E119", "I10", "J069", "M545", "Z0000", "E785", "F329", "K219", "R109", "N390"]

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
LEGACY_DATE_FMT = "%m/%d/%Y"          # legacy systems send MM/DD/YYYY
HIGH_DATE = "12/31/9999"


def d(dt: date) -> str:
    return dt.strftime(LEGACY_DATE_FMT)


def rand_date(rng, start: date, end: date) -> date:
    return start + timedelta(days=rng.randint(0, (end - start).days))


def phone(rng) -> str:
    return f"{rng.randint(200, 989)}{rng.randint(200, 999)}{rng.randint(1000, 9999)}"


def address(rng):
    city, state, zip3 = rng.choice(CITIES)
    return (f"{rng.randint(100, 9999)} {rng.choice(STREETS)}", city, state,
            f"{zip3}{rng.randint(10, 99)}")


def write_pipe_file(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write("|".join(header) + "\n")
        for r in rows:
            fh.write("|".join("" if v is None else str(v) for v in r) + "\n")


# --------------------------------------------------------------------------
# Generator
# --------------------------------------------------------------------------
def generate(out_dir, n_groups, n_subscribers, n_providers, n_claims, seed):
    rng = random.Random(seed)
    issues = {}

    def log_issue(key, sample):
        entry = issues.setdefault(key, {"count": 0, "samples": []})
        entry["count"] += 1
        if len(entry["samples"]) < 5:
            entry["samples"].append(sample)

    os.makedirs(out_dir, exist_ok=True)

    # ---------------- GROUPS ----------------
    group_hdr = ["GROUP_NUMBER", "GROUP_NAME", "LOB_CODE", "GROUP_STATUS", "GROUP_EFF_DATE",
                 "GROUP_TERM_DATE", "ADDRESS_LINE1", "CITY", "STATE", "ZIP_CODE", "PHONE"]
    groups = []
    for i in range(1, n_groups + 1):
        gid = f"G{i:04d}"
        lob = rng.choices(list(LOB_PLANS), weights=[70, 20, 10])[0]
        a1, city, st, z = address(rng)
        eff = rand_date(rng, date(2015, 1, 1), date(2023, 1, 1)).replace(day=1)
        groups.append([gid, f"{rng.choice(COMPANY_WORDS)} {rng.choice(COMPANY_TYPES)}",
                       lob, "A", d(eff), HIGH_DATE, a1, city, st, z, phone(rng)])
    # injected: a group with a missing group name (profiling null check)
    groups[3][1] = None
    log_issue("GROUP_NAME_NULL", groups[3][0])
    group_lob = {g[0]: g[2] for g in groups}
    group_ids = list(group_lob)

    # ---------------- MEMBERS ----------------
    mem_hdr = ["MEMBER_ID", "SUBSCRIBER_ID", "RELATIONSHIP_CODE", "FIRST_NAME", "LAST_NAME",
               "MIDDLE_INITIAL", "DATE_OF_BIRTH", "GENDER_CODE", "SSN", "ADDRESS_LINE1",
               "CITY", "STATE", "ZIP_CODE", "PHONE", "GROUP_NUMBER", "PLAN_CODE",
               "COVERAGE_EFF_DATE", "COVERAGE_TERM_DATE"]
    members = []
    mem_seq = 0
    for _ in range(n_subscribers):
        gid = rng.choice(group_ids)
        plan = rng.choice(LOB_PLANS[group_lob[gid]])
        a1, city, st, z = address(rng)
        last = rng.choice(LAST_NAMES)
        cov_eff = rand_date(rng, date(2020, 1, 1), date(2025, 6, 1)).replace(day=1)
        cov_term = HIGH_DATE if rng.random() > 0.12 else d(
            rand_date(rng, cov_eff + timedelta(days=60), date(2026, 6, 30)))
        family = [("18", None)]  # X12 relationship codes: 18=self, 01=spouse, 19=child
        if rng.random() < 0.55:
            family.append(("01", None))
        for _k in range(rng.choices([0, 1, 2, 3], weights=[40, 25, 25, 10])[0]):
            family.append(("19", None))
        sub_id = None
        sub_gender = rng.choice("MF")
        for rel, _ in family:
            mem_seq += 1
            mid = f"M{mem_seq:07d}"
            if rel == "18":
                sub_id = mid
                gender = sub_gender
                dob = rand_date(rng, date(1955, 1, 1), date(2000, 12, 31))
            elif rel == "01":
                gender = "F" if sub_gender == "M" else "M"
                dob = rand_date(rng, date(1955, 1, 1), date(2000, 12, 31))
            else:
                gender = rng.choice("MF")
                dob = rand_date(rng, date(2002, 1, 1), date(2024, 12, 31))
            first = rng.choice(FIRST_NAMES_M if gender == "M" else FIRST_NAMES_F)
            ssn = f"{rng.randint(100, 899)}{rng.randint(10, 99)}{rng.randint(1000, 9999)}"
            members.append([mid, sub_id, rel, first, last, rng.choice("ABCDEJKLMRS "),
                            d(dob), gender, ssn, a1, city, st, z, phone(rng), gid, plan,
                            d(cov_eff), cov_term])

    # -- injected member issues --
    subs = [m for m in members if m[2] == "18"]
    deps = [m for m in members if m[2] != "18"]
    for m in rng.sample(members, 12):            # legacy numeric gender codes (mappable)
        m[7] = "1" if m[7] == "M" else "2"
        log_issue("GENDER_LEGACY_NUMERIC_CODE (mapped via crosswalk)", m[0])
    for m in rng.sample(deps, 4):                # unmapped gender -> reject
        m[7] = "X"
        log_issue("GENDER_UNMAPPED_X (reject)", m[0])
    for m in rng.sample(deps, 5):                # null DOB -> reject
        m[6] = None
        log_issue("DOB_NULL (reject)", m[0])
    for m, bad in zip(rng.sample(deps, 3), ["02/30/1985", "13/01/1990", "1988-07-14"]):
        m[6] = bad                                # invalid date -> reject
        log_issue("DOB_INVALID_DATE (reject)", f"{m[0]}={bad}")
    for m, bad in zip(rng.sample(members, 8),
                      ["José", "MarÃ­a", "Ann\tMarie", "Peña",
                       "Chloë", "Renée", "Zoë", "Björn"]):
        m[3] = bad                                # non-ASCII / control chars -> cleansed
        log_issue("FIRST_NAME_INVALID_CHARACTERS (cleansed)", f"{m[0]}={bad!r}")
    for m in rng.sample(members, 6):              # SSN with dashes -> cleansed
        s = m[8]
        m[8] = f"{s[:3]}-{s[3:5]}-{s[5:]}"
        log_issue("SSN_WITH_DASHES (cleansed)", m[0])
    for m in rng.sample(members, 3):              # garbage SSN -> set NULL + warning
        m[8] = "UNKNOWN"
        log_issue("SSN_INVALID (nulled)", m[0])
    for m in rng.sample(subs, 2):                 # group not on group file -> reject family
        fam = [x for x in members if x[1] == m[0]]
        for x in fam:
            x[14] = "G9999"
        log_issue("GROUP_NOT_FOUND (subscriber + dependents reject)", m[0])
    for m in rng.sample(subs, 2):                 # unmapped plan code -> reject family
        for x in [x for x in members if x[1] == m[0]]:
            x[15] = "P999"
        log_issue("PLAN_XWALK_NOT_FOUND (subscriber + dependents reject)", m[0])
    for m in rng.sample(members, 3):              # whitespace padding -> trimmed
        m[4] = f"  {m[4]} "
        log_issue("LAST_NAME_PADDED_SPACES (trimmed)", m[0])
    dup_rows = [list(m) for m in rng.sample(members, 10)]  # exact duplicates -> reject 2nd
    for m in dup_rows:
        log_issue("DUPLICATE_MEMBER_ROW (reject duplicate)", m[0])
    members.extend(dup_rows)
    rng.shuffle(members)

    # ---------------- PROVIDERS ----------------
    prov_hdr = ["PROVIDER_ID", "NPI", "PROVIDER_TYPE", "FIRST_NAME", "LAST_NAME",
                "ORGANIZATION_NAME", "SPECIALTY_CODE", "TAX_ID", "ADDRESS_LINE1", "CITY",
                "STATE", "ZIP_CODE", "NETWORK_STATUS", "PROVIDER_EFF_DATE"]
    providers = []
    for i in range(1, n_providers + 1):
        pid = f"P{i:05d}"
        a1, city, st, z = address(rng)
        npi = f"1{rng.randint(100000000, 999999999)}"
        if rng.random() < 0.75:
            g = rng.choice("MF")
            row = [pid, npi, "IND", rng.choice(FIRST_NAMES_M if g == "M" else FIRST_NAMES_F),
                   rng.choice(LAST_NAMES), None]
        else:
            row = [pid, npi, "ORG", None, None,
                   f"{rng.choice(COMPANY_WORDS)} {rng.choice(['Medical Group', 'Clinic', 'Hospital', 'Imaging Center', 'Labs'])}"]
        row += [rng.choice(SPECIALTIES), f"{rng.randint(10, 99)}{rng.randint(1000000, 9999999)}",
                a1, city, st, z, rng.choices(["PAR", "NONPAR"], weights=[85, 15])[0],
                d(rand_date(rng, date(2010, 1, 1), date(2022, 1, 1)))]
        providers.append(row)
    for p in rng.sample(providers, 3):            # invalid state -> reject (config check)
        p[10] = "XX"
        log_issue("PROVIDER_INVALID_STATE (reject)", p[0])
    for p in rng.sample(providers, 2):            # NPI wrong length -> profiling + warn
        p[1] = p[1][:8]
        log_issue("PROVIDER_NPI_WRONG_LENGTH (warning)", p[0])
    bad_prov = {p[0] for p in providers if p[10] == "XX"}

    # ---------------- CLAIMS ----------------
    clm_hdr = ["CLAIM_ID", "MEMBER_ID", "PROVIDER_ID", "CLAIM_TYPE", "CLAIM_STATUS",
               "RECEIVED_DATE", "SERVICE_FROM_DATE", "SERVICE_TO_DATE", "TOTAL_CHARGE_AMT",
               "TOTAL_PAID_AMT", "PRIMARY_DIAG_CODE", "SECONDARY_DIAG_CODE"]
    line_hdr = ["CLAIM_ID", "LINE_NUMBER", "PROCEDURE_CODE", "PROCEDURE_MODIFIER",
                "SERVICE_DATE", "UNITS", "CHARGE_AMT", "ALLOWED_AMT", "PAID_AMT", "LINE_STATUS"]
    unique_members = {m[0]: m for m in members}
    member_pool = list(unique_members)
    prov_pool = [p[0] for p in providers]
    claims, lines = [], []
    for i in range(1, n_claims + 1):
        cid = f"C{i:09d}"
        mid = rng.choice(member_pool)
        status = rng.choices(["PAID", "DENIED", "PEND"], weights=[78, 15, 7])[0]
        svc_from = rand_date(rng, date(2024, 1, 1), date(2026, 6, 30))
        svc_to = svc_from + timedelta(days=rng.choice([0, 0, 0, 0, 1, 2, 3]))
        received = svc_to + timedelta(days=rng.randint(2, 45))
        n_lines = rng.choices([1, 2, 3, 4], weights=[40, 30, 20, 10])[0]
        tot_chg = tot_paid = 0.0
        for ln in range(1, n_lines + 1):
            units = rng.choice([1, 1, 1, 2, 3])
            chg = round(rng.uniform(40, 650) * units, 2)
            allowed = round(chg * rng.uniform(0.45, 0.85), 2)
            paid = round(allowed * rng.uniform(0.7, 1.0), 2) if status == "PAID" else 0.0
            tot_chg += chg
            tot_paid += paid
            lines.append([cid, ln, rng.choice(PROC_CODES), rng.choice(["", "", "", "25", "59", "GT"]),
                          d(svc_from + timedelta(days=min(ln - 1, (svc_to - svc_from).days))),
                          units, f"{chg:.2f}", f"{allowed:.2f}", f"{paid:.2f}",
                          "P" if status == "PAID" else ("D" if status == "DENIED" else "H")])
        claims.append([cid, mid, rng.choice(prov_pool), "M", status, d(received), d(svc_from),
                       d(svc_to), f"{tot_chg:.2f}", f"{tot_paid:.2f}", rng.choice(DIAG_CODES),
                       rng.choice(DIAG_CODES + [""] * 6)])
    for c in rng.sample(claims, 4):               # member not on member file -> reject
        c[1] = "M9999999"
        log_issue("CLAIM_MEMBER_NOT_FOUND (reject)", c[0])
    for c in rng.sample(claims, 3):               # from > to -> reject
        c[6], c[7] = c[7], c[6]
        if c[6] == c[7]:
            c[7] = d(date(2023, 1, 1))
        log_issue("CLAIM_SERVICE_FROM_AFTER_TO (reject)", c[0])
    for c in rng.sample(claims, 2):               # unknown status -> reject via crosswalk
        c[4] = "VOID?"
        log_issue("CLAIM_STATUS_UNMAPPED (reject)", c[0])
    n_cascade = sum(1 for c in claims if c[2] in bad_prov)
    if n_cascade:
        issues["CLAIM_PROVIDER_NOT_LOADED (cascade reject)"] = {
            "count": n_cascade, "samples": [c[0] for c in claims if c[2] in bad_prov][:5]}
    for k in range(3):                            # orphan lines (no header) -> reject
        orphan = f"C8{k:08d}"
        lines.append([orphan, 1, "99213", "", "03/15/2025", 1, "120.00", "80.00", "64.00", "P"])
        log_issue("CLAIM_LINE_ORPHAN (reject)", orphan)
    for ln in rng.sample(lines, 3):               # negative paid -> warning test
        ln[8] = f"-{ln[8]}" if not ln[8].startswith("-") else ln[8]
        log_issue("CLAIM_LINE_NEGATIVE_PAID (warning)", f"{ln[0]}-{ln[1]}")

    # ---------------- WRITE ----------------
    write_pipe_file(os.path.join(out_dir, "SRC_GROUP.txt"), group_hdr, groups)
    write_pipe_file(os.path.join(out_dir, "SRC_MEMBER.txt"), mem_hdr, members)
    write_pipe_file(os.path.join(out_dir, "SRC_PROVIDER.txt"), prov_hdr, providers)
    write_pipe_file(os.path.join(out_dir, "SRC_CLAIM_HEADER.txt"), clm_hdr, claims)
    write_pipe_file(os.path.join(out_dir, "SRC_CLAIM_LINE.txt"), line_hdr, lines)

    counts = {"SRC_GROUP": len(groups), "SRC_MEMBER": len(members),
              "SRC_MEMBER (subscribers, RELATIONSHIP_CODE=18)": sum(1 for m in members if m[2] == "18"),
              "SRC_PROVIDER": len(providers), "SRC_CLAIM_HEADER": len(claims),
              "SRC_CLAIM_LINE": len(lines)}
    with open(os.path.join(out_dir, "_injected_issues.json"), "w", encoding="utf-8") as fh:
        json.dump({"seed": seed, "row_counts": counts, "injected_issues": issues}, fh,
                  indent=2, ensure_ascii=False)
    return counts, issues


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--batch", default="BATCH_001", help="batch id / output sub-folder")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "data", "source"))
    ap.add_argument("--groups", type=int, default=60)
    ap.add_argument("--subscribers", type=int, default=1500)
    ap.add_argument("--providers", type=int, default=350)
    ap.add_argument("--claims", type=int, default=8000)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    out_dir = os.path.abspath(os.path.join(a.out, a.batch))
    counts, issues = generate(out_dir, a.groups, a.subscribers, a.providers, a.claims, a.seed)
    print(f"Files written to: {out_dir}")
    for k, v in counts.items():
        print(f"  {k:<48} {v:>7,} rows")
    print("\nInjected data-quality issues:")
    for k, v in issues.items():
        print(f"  {k:<60} {v['count']:>4}")


if __name__ == "__main__":
    main()
