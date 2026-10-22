# CryoMatrix

Genomic repository and cold-chain telemetry ledger.

CryoMatrix is a relational database system for tracking where cryogenic biological specimens are stored, who handled them, and what temperatures they were exposed to. It is built with MySQL on XAMPP as the project for CSE311L (Database Management System Lab) at North South University.

## Status

Proposal stage. The proposal was submitted on 22 October 2026. The schema, seed data, and web interface do not exist yet, and nothing in this repository should be read as a working system. This README describes what the team has committed to building and will be updated as each part lands.

## The problem

Biobanks and genomic research institutes store thousands of specimens that degrade if their storage allocation or chain-of-custody records are wrong. When liquid nitrogen dewar capacity, rack positions, and researcher access are tracked in separate spreadsheets, specimens get misplaced and compliance audits fail. Transfers, thaws for clinical trials, and biohazard audits all need consistent records, which is why this project uses a relational database with enforced constraints and transactions instead of spreadsheets.

## Planned scope

**Cryo-storage mapping.** Each specimen's location is recorded down the hierarchy: laboratory zone, liquid nitrogen dewar, vertical rack, cryobox slot. The schema should make it impossible to assign two specimens to the same slot.

**Specimen types and lifecycle.** Genomic DNA, cryo-plasma, and tissue cultures get their own tables, modeled as an EER specialization of a general specimen entity. The system tracks freeze-thaw cycle counts and expiration dates.

**Chain of custody.** Every check-out, internal transfer, and return is logged against a researcher ID and an approved clinical trial protocol.

**Thermal excursions and quarantine.** Freezer temperature logs are stored. When an excursion is recorded, SQL update queries flag every specimen in the affected dewar for quality quarantine.

**De-identified donor view.** Donor demographic data is kept separate from specimen vial barcodes. Relational views expose only de-identified data to enforce privacy and keep the database ready for audit.

## Technology

- Database: MySQL, hosted locally through XAMPP
- Frontend: HTML and CSS, for the specimen search and checkout forms
- Server-side scripting: PHP, running on XAMPP's Apache server

## Design targets

- Schema normalized to 3NF
- Foreign key constraints enforced across the storage hierarchy and custody tables
- E-R and EER diagrams, with a mapped relational schema
- Realistic seed data representing a biobank
- Testing of CRUD operations against the constraints

## Team

Team 02, Section 04, CSE311L.

| Member | Role |
| --- | --- |
| Parthib Sikder | Lead database architect and backend developer. Designs the 3NF schema, enforces foreign keys, writes core backend queries. |
| Faizuddin Safa | Conceptual data modeler and SQL query engineer. Builds the E-R and EER diagrams, maps the relational schema, writes DDL/DML and analytical views. |
| Moumita Haider Oishe | Frontend and dashboard developer. Builds the web interface and search/checkout forms, integrates them with XAMPP. |
| Nishat Tasnim | Data integrity, QA, and documentation lead. Populates seed data, tests constraints, compiles project documentation. |

## Course information

- University: North South University, Department of Electrical and Computer Engineering
- Course: CSE311L, Database Management System Lab
- Faculty: Rifat Ahmed Hassan (RIH)
- Lab instructor: Md. Amanullah Shah

## Repository layout

To be added once the first schema and diagrams are committed.

## Setup

To be added. Instructions for importing the schema and seed data into XAMPP's MySQL will go here once those files exist.

## License

Licensed under the Apache License, Version 2.0. See the `LICENSE` file for the full text.
