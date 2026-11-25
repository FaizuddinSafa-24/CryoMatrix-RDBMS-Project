-- =====================================================================
-- CSE311L FALL 2026 - Group 02
-- CryoMatrix: Cryogenic Biological Specimen Management System
-- COMPLETE DATABASE IMPLEMENTATION (single file)
--
--   Part 1: Create database, tables, constraints, view, base triggers
--   Part 2: Sample data (INSERT values for all 11 tables)
--   Part 3: Stored procedures + temperature-excursion trigger
--
-- Import this one file in phpMyAdmin (Import tab) or run:
--   mysql -u root -p < Group02_CSE311L_cryo_biobank.sql
-- Tested on MariaDB (the engine XAMPP ships); loads with no errors.
-- =====================================================================

-- #####################################################################
-- PART 1: SCHEMA
-- #####################################################################
-- =====================================================================
-- CSE311L FALL 2026 - Group 02
-- Cryogenic Biological Specimen Management System
-- Step 3: Physical schema (DDL) - MySQL 8.0+ / MariaDB 10.4+
-- =====================================================================

DROP DATABASE IF EXISTS cryo_biobank;
CREATE DATABASE cryo_biobank CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cryo_biobank;

-- ---------------------------------------------------------------------
-- DONOR
-- ---------------------------------------------------------------------
CREATE TABLE DONOR (
    donor_id        INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    birth_year      SMALLINT     NOT NULL,
    biological_sex  ENUM('MALE','FEMALE','INTERSEX','UNKNOWN') NOT NULL,
    consent_status  ENUM('GRANTED','PENDING','WITHDRAWN') NOT NULL DEFAULT 'PENDING',
    CONSTRAINT chk_donor_birth_year CHECK (birth_year BETWEEN 1900 AND 2100)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- DEWAR (liquid-nitrogen storage tank)
-- ---------------------------------------------------------------------
CREATE TABLE DEWAR (
    dewar_id         INT AUTO_INCREMENT PRIMARY KEY,
    lab_zone         VARCHAR(50)  NOT NULL,
    min_safe_temp_c  DECIMAL(6,2) NOT NULL,
    max_safe_temp_c  DECIMAL(6,2) NOT NULL,
    CONSTRAINT chk_dewar_temp_range CHECK (min_safe_temp_c < max_safe_temp_c),
    CONSTRAINT chk_dewar_min_temp   CHECK (min_safe_temp_c >= -273.15)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- STORAGE_SLOT  (dewar -> rack -> cryobox -> slot coordinate)
-- UQ_COORD: one physical coordinate = one slot row
-- ---------------------------------------------------------------------
CREATE TABLE STORAGE_SLOT (
    slot_id       INT AUTO_INCREMENT PRIMARY KEY,
    dewar_id      INT         NOT NULL,
    rack_code     VARCHAR(10) NOT NULL,
    cryobox_code  VARCHAR(10) NOT NULL,
    slot_code     VARCHAR(10) NOT NULL,
    CONSTRAINT uq_coord UNIQUE (dewar_id, rack_code, cryobox_code, slot_code),
    CONSTRAINT fk_slot_dewar FOREIGN KEY (dewar_id)
        REFERENCES DEWAR(dewar_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- SPECIMEN  (supertype)
-- slot_id is UNIQUE + NULLable: one vial per slot, NULL = checked out
-- ---------------------------------------------------------------------
CREATE TABLE SPECIMEN (
    specimen_id        INT AUTO_INCREMENT PRIMARY KEY,
    vial_barcode       VARCHAR(30) NOT NULL,
    donor_id           INT         NOT NULL,
    slot_id            INT         NULL,
    specimen_type      ENUM('GENOMIC_DNA','CRYO_PLASMA','TISSUE_CULTURE') NOT NULL,
    freeze_thaw_count  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    expiration_date    DATE        NOT NULL,
    quality_status     ENUM('VIABLE','COMPROMISED','QUARANTINED','DISCARDED') NOT NULL DEFAULT 'VIABLE',
    CONSTRAINT uq_specimen_barcode UNIQUE (vial_barcode),
    CONSTRAINT uq_specimen_slot    UNIQUE (slot_id),
    CONSTRAINT chk_freeze_thaw     CHECK (freeze_thaw_count <= 20),
    CONSTRAINT fk_specimen_donor FOREIGN KEY (donor_id)
        REFERENCES DONOR(donor_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_specimen_slot FOREIGN KEY (slot_id)
        REFERENCES STORAGE_SLOT(slot_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Subtypes (IS_A_DNA / IS_A_PLASMA / IS_A_TISSUE) - shared PK
-- ---------------------------------------------------------------------
CREATE TABLE GENOMIC_DNA (
    specimen_id          INT PRIMARY KEY,
    concentration_ng_ul  DECIMAL(8,2) NOT NULL,
    CONSTRAINT chk_dna_conc CHECK (concentration_ng_ul > 0),
    CONSTRAINT fk_dna_specimen FOREIGN KEY (specimen_id)
        REFERENCES SPECIMEN(specimen_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE CRYO_PLASMA (
    specimen_id         INT PRIMARY KEY,
    anticoagulant_type  ENUM('EDTA','HEPARIN','CITRATE','ACD') NOT NULL,
    CONSTRAINT fk_plasma_specimen FOREIGN KEY (specimen_id)
        REFERENCES SPECIMEN(specimen_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE TISSUE_CULTURE (
    specimen_id     INT PRIMARY KEY,
    passage_number  SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT chk_passage CHECK (passage_number BETWEEN 1 AND 200),
    CONSTRAINT fk_tissue_specimen FOREIGN KEY (specimen_id)
        REFERENCES SPECIMEN(specimen_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- RESEARCHER
-- ---------------------------------------------------------------------
CREATE TABLE RESEARCHER (
    researcher_id     INT AUTO_INCREMENT PRIMARY KEY,
    full_name         VARCHAR(100) NOT NULL,
    clearance_status  ENUM('CLEARED','PENDING','SUSPENDED','REVOKED') NOT NULL DEFAULT 'PENDING'
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- CLINICAL_PROTOCOL
-- ---------------------------------------------------------------------
CREATE TABLE CLINICAL_PROTOCOL (
    protocol_id      INT AUTO_INCREMENT PRIMARY KEY,
    protocol_code    VARCHAR(30) NOT NULL,
    approval_status  ENUM('APPROVED','UNDER_REVIEW','SUSPENDED','EXPIRED') NOT NULL DEFAULT 'UNDER_REVIEW',
    CONSTRAINT uq_protocol_code UNIQUE (protocol_code)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- CUSTODY_LOG  (chain of custody; append-only audit trail)
-- ---------------------------------------------------------------------
CREATE TABLE CUSTODY_LOG (
    custody_id     INT AUTO_INCREMENT PRIMARY KEY,
    specimen_id    INT NOT NULL,
    researcher_id  INT NOT NULL,
    protocol_id    INT NOT NULL,
    slot_id        INT NOT NULL,
    action_type    ENUM('DEPOSIT','RETRIEVE','RETURN','TRANSFER','DISPOSE') NOT NULL,
    logged_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_custody_specimen FOREIGN KEY (specimen_id)
        REFERENCES SPECIMEN(specimen_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_custody_researcher FOREIGN KEY (researcher_id)
        REFERENCES RESEARCHER(researcher_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_custody_protocol FOREIGN KEY (protocol_id)
        REFERENCES CLINICAL_PROTOCOL(protocol_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_custody_slot FOREIGN KEY (slot_id)
        REFERENCES STORAGE_SLOT(slot_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_custody_specimen_time (specimen_id, logged_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- TEMPERATURE_LOG  (thermal chain)
-- ---------------------------------------------------------------------
CREATE TABLE TEMPERATURE_LOG (
    temp_log_id      INT AUTO_INCREMENT PRIMARY KEY,
    dewar_id         INT NOT NULL,
    recorded_temp_c  DECIMAL(6,2) NOT NULL,
    recorded_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_temp_dewar FOREIGN KEY (dewar_id)
        REFERENCES DEWAR(dewar_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_temp_dewar_time (dewar_id, recorded_at)
) ENGINE=InnoDB;

-- =====================================================================
-- VIEW: de-identified specimens (no donor name / donor_id exposed)
-- =====================================================================
CREATE OR REPLACE VIEW vw_deidentified_specimens AS
SELECT  s.vial_barcode,
        s.specimen_type,
        s.freeze_thaw_count,
        s.expiration_date,
        s.quality_status,
        d.lab_zone,
        d.dewar_id,
        ss.rack_code,
        ss.cryobox_code,
        ss.slot_code,
        g.concentration_ng_ul,
        p.anticoagulant_type,
        t.passage_number,
        dn.birth_year      AS donor_birth_year,
        dn.biological_sex  AS donor_biological_sex,
        dn.consent_status  AS donor_consent_status
FROM        SPECIMEN       s
JOIN        DONOR          dn ON dn.donor_id   = s.donor_id
LEFT JOIN   STORAGE_SLOT   ss ON ss.slot_id    = s.slot_id
LEFT JOIN   DEWAR          d  ON d.dewar_id    = ss.dewar_id
LEFT JOIN   GENOMIC_DNA    g  ON g.specimen_id = s.specimen_id
LEFT JOIN   CRYO_PLASMA    p  ON p.specimen_id = s.specimen_id
LEFT JOIN   TISSUE_CULTURE t  ON t.specimen_id = s.specimen_id;

-- =====================================================================
-- TRIGGERS: business rules that CHECK constraints cannot express
-- =====================================================================
DELIMITER $$

-- Rule 1: only donors with GRANTED consent can have new specimens
CREATE TRIGGER trg_specimen_consent_check
BEFORE INSERT ON SPECIMEN
FOR EACH ROW
BEGIN
    IF (SELECT consent_status FROM DONOR WHERE donor_id = NEW.donor_id) <> 'GRANTED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Donor consent is not GRANTED; specimen cannot be registered.';
    END IF;
END$$

-- Rule 2 (disjoint specialization): subtype row must match specimen_type
CREATE TRIGGER trg_dna_type_check
BEFORE INSERT ON GENOMIC_DNA
FOR EACH ROW
BEGIN
    IF (SELECT specimen_type FROM SPECIMEN WHERE specimen_id = NEW.specimen_id) <> 'GENOMIC_DNA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specimen is not of type GENOMIC_DNA.';
    END IF;
END$$

CREATE TRIGGER trg_plasma_type_check
BEFORE INSERT ON CRYO_PLASMA
FOR EACH ROW
BEGIN
    IF (SELECT specimen_type FROM SPECIMEN WHERE specimen_id = NEW.specimen_id) <> 'CRYO_PLASMA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specimen is not of type CRYO_PLASMA.';
    END IF;
END$$

CREATE TRIGGER trg_tissue_type_check
BEFORE INSERT ON TISSUE_CULTURE
FOR EACH ROW
BEGIN
    IF (SELECT specimen_type FROM SPECIMEN WHERE specimen_id = NEW.specimen_id) <> 'TISSUE_CULTURE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specimen is not of type TISSUE_CULTURE.';
    END IF;
END$$

-- Rule 3: custody actions need a CLEARED researcher under an APPROVED protocol
CREATE TRIGGER trg_custody_clearance_check
BEFORE INSERT ON CUSTODY_LOG
FOR EACH ROW
BEGIN
    IF (SELECT clearance_status FROM RESEARCHER WHERE researcher_id = NEW.researcher_id) <> 'CLEARED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Researcher does not hold CLEARED status.';
    END IF;
    IF (SELECT approval_status FROM CLINICAL_PROTOCOL WHERE protocol_id = NEW.protocol_id) <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Clinical protocol is not APPROVED.';
    END IF;
END$$

-- Rule 4: custody log is append-only (tamper-proof audit trail)
CREATE TRIGGER trg_custody_no_update
BEFORE UPDATE ON CUSTODY_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CUSTODY_LOG is append-only; updates are not allowed.';
END$$

CREATE TRIGGER trg_custody_no_delete
BEFORE DELETE ON CUSTODY_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CUSTODY_LOG is append-only; deletes are not allowed.';
END$$

-- Rule 5: a RETRIEVE increments the freeze-thaw counter and frees the slot
CREATE TRIGGER trg_custody_after_insert
AFTER INSERT ON CUSTODY_LOG
FOR EACH ROW
BEGIN
    IF NEW.action_type = 'RETRIEVE' THEN
        UPDATE SPECIMEN
           SET freeze_thaw_count = freeze_thaw_count + 1,
               slot_id = NULL
         WHERE specimen_id = NEW.specimen_id;
    ELSEIF NEW.action_type IN ('DEPOSIT','RETURN','TRANSFER') THEN
        UPDATE SPECIMEN SET slot_id = NEW.slot_id
         WHERE specimen_id = NEW.specimen_id;
    ELSEIF NEW.action_type = 'DISPOSE' THEN
        UPDATE SPECIMEN SET slot_id = NULL, quality_status = 'DISCARDED'
         WHERE specimen_id = NEW.specimen_id;
    END IF;
END$$

DELIMITER ;

-- #####################################################################
-- PART 2: SAMPLE DATA
-- #####################################################################
-- =====================================================================
-- CSE311L FALL 2026 - Group 02
-- CryoMatrix: Cryogenic Biological Specimen Management System
-- Step 4: Sample data (DML) - EXPANDED VERSION
-- Prepared by: Tasnim Nishat (Data Integrity, QA & Documentation Lead)
-- Run AFTER 01_schema.sql
--
-- Rows per table:
--   DONOR 14 | DEWAR 4 | STORAGE_SLOT 30 | SPECIMEN 24
--   GENOMIC_DNA 8 | CRYO_PLASMA 8 | TISSUE_CULTURE 8
--   RESEARCHER 8 | CLINICAL_PROTOCOL 6 | CUSTODY_LOG 46 | TEMPERATURE_LOG 24
--
-- Rows 1-9 of SPECIMEN (and the first rows of every table) are the
-- original dataset; IDs are kept the same so 03_queries.sql still works.
-- =====================================================================
USE cryo_biobank;

-- DONOR -----------------------------------------------------------------
-- 12 GRANTED, 1 WITHDRAWN (id 5), 1 PENDING (id 6), + 1 PENDING (id 14).
-- Donors 5, 6 and 14 have NO specimens: the consent trigger blocks them.
INSERT INTO DONOR (full_name, birth_year, biological_sex, consent_status) VALUES
('Rahim Uddin',        1985, 'MALE',    'GRANTED'),    -- 1
('Nusrat Jahan',       1992, 'FEMALE',  'GRANTED'),    -- 2
('Kamal Hossain',      1978, 'MALE',    'GRANTED'),    -- 3
('Farzana Akter',      2000, 'FEMALE',  'GRANTED'),    -- 4
('Sabbir Ahmed',       1965, 'MALE',    'WITHDRAWN'),  -- 5
('Tahmina Rahman',     1998, 'FEMALE',  'PENDING'),    -- 6
('Mehedi Hasan',       1990, 'MALE',    'GRANTED'),    -- 7
('Sharmin Sultana',    1987, 'FEMALE',  'GRANTED'),    -- 8
('Arif Mahmud',        1972, 'MALE',    'GRANTED'),    -- 9
('Rumana Begum',       1983, 'FEMALE',  'GRANTED'),    -- 10
('Tanvir Rahman',      1995, 'MALE',    'GRANTED'),    -- 11
('Jannatul Ferdous',   2001, 'FEMALE',  'GRANTED'),    -- 12 (withdraws later, see below)
('Habibur Rahman',     1958, 'MALE',    'GRANTED'),    -- 13
('Shirin Akhter',      1969, 'FEMALE',  'PENDING');    -- 14

-- DEWAR -----------------------------------------------------------------
-- Vapour-phase LN2 tanks are kept roughly between -196 C and -150 C
INSERT INTO DEWAR (lab_zone, min_safe_temp_c, max_safe_temp_c) VALUES
('ZONE-A', -196.00, -150.00),   -- 1
('ZONE-A', -196.00, -150.00),   -- 2
('ZONE-B', -196.00, -135.00),   -- 3
('ZONE-C', -196.00, -150.00);   -- 4 (new tank)

-- STORAGE_SLOT ----------------------------------------------------------
-- Coordinate = dewar / rack / cryobox / slot. 30 slots; 9 are empty once all custody actions have run.
INSERT INTO STORAGE_SLOT (dewar_id, rack_code, cryobox_code, slot_code) VALUES
(1, 'R01', 'BX01', 'A1'), (1, 'R01', 'BX01', 'A2'), (1, 'R01', 'BX01', 'A3'),   -- 1-3
(1, 'R02', 'BX05', 'B1'), (2, 'R01', 'BX02', 'A1'), (2, 'R01', 'BX02', 'A2'),   -- 4-6
(2, 'R03', 'BX09', 'C4'), (3, 'R01', 'BX01', 'A1'), (3, 'R01', 'BX01', 'A2'),   -- 7-9
(3, 'R02', 'BX03', 'D7'), (3, 'R02', 'BX03', 'D8'), (3, 'R02', 'BX03', 'D9'),   -- 10-12
(2, 'R02', 'BX04', 'A1'), (2, 'R02', 'BX04', 'A2'), (2, 'R02', 'BX04', 'A3'),   -- 13-15
(3, 'R03', 'BX06', 'E1'), (3, 'R03', 'BX06', 'E2'),                             -- 16-17
(4, 'R01', 'BX01', 'A1'), (4, 'R01', 'BX01', 'A2'), (4, 'R01', 'BX01', 'A3'),   -- 18-20
(4, 'R01', 'BX01', 'A4'), (4, 'R01', 'BX01', 'A5'), (4, 'R01', 'BX01', 'A6'),   -- 21-23
(4, 'R02', 'BX02', 'B1'), (4, 'R02', 'BX02', 'B2'), (4, 'R02', 'BX02', 'B3'),   -- 24-26
(4, 'R02', 'BX02', 'B4'),                                                       -- 27
(1, 'R02', 'BX05', 'B2'), (1, 'R02', 'BX05', 'B3'),                             -- 28-29
(2, 'R03', 'BX09', 'C5');                                                       -- 30

-- SPECIMEN --------------------------------------------------------------
-- 24 vials: 8 GENOMIC_DNA, 8 CRYO_PLASMA, 8 TISSUE_CULTURE.
-- Only donors with GRANTED consent are used.
INSERT INTO SPECIMEN (vial_barcode, donor_id, slot_id, specimen_type, freeze_thaw_count, expiration_date, quality_status) VALUES
('VB-DNA-0001', 1,  1,  'GENOMIC_DNA',    0, '2030-12-31', 'VIABLE'),        -- 1
('VB-DNA-0002', 2,  2,  'GENOMIC_DNA',    2, '2029-06-30', 'VIABLE'),        -- 2
('VB-DNA-0003', 3,  5,  'GENOMIC_DNA',    5, '2026-10-01', 'COMPROMISED'),   -- 3
('VB-PLS-0001', 1,  3,  'CRYO_PLASMA',    1, '2028-03-15', 'VIABLE'),        -- 4
('VB-PLS-0002', 4,  6,  'CRYO_PLASMA',    0, '2027-01-20', 'VIABLE'),        -- 5
('VB-PLS-0003', 2,  8,  'CRYO_PLASMA',    3, '2026-11-30', 'QUARANTINED'),   -- 6
('VB-TIS-0001', 3,  9,  'TISSUE_CULTURE', 0, '2031-05-05', 'VIABLE'),        -- 7
('VB-TIS-0002', 4,  10, 'TISSUE_CULTURE', 1, '2029-09-09', 'VIABLE'),        -- 8
('VB-TIS-0003', 1,  11, 'TISSUE_CULTURE', 4, '2026-08-15', 'COMPROMISED'),   -- 9
('VB-DNA-0004', 7,  13, 'GENOMIC_DNA',    0, '2032-04-30', 'VIABLE'),        -- 10
('VB-DNA-0005', 8,  14, 'GENOMIC_DNA',    1, '2031-07-15', 'VIABLE'),        -- 11
('VB-DNA-0006', 9,  18, 'GENOMIC_DNA',    0, '2030-02-28', 'VIABLE'),        -- 12
('VB-DNA-0007', 12, 19, 'GENOMIC_DNA',    0, '2031-11-01', 'VIABLE'),        -- 13
('VB-DNA-0008', 13, 24, 'GENOMIC_DNA',    3, '2027-02-10', 'VIABLE'),        -- 14
('VB-PLS-0004', 7,  15, 'CRYO_PLASMA',    0, '2028-08-08', 'VIABLE'),        -- 15
('VB-PLS-0005', 10, 16, 'CRYO_PLASMA',    2, '2027-05-31', 'VIABLE'),        -- 16
('VB-PLS-0006', 11, 20, 'CRYO_PLASMA',    0, '2028-12-12', 'VIABLE'),        -- 17
('VB-PLS-0007', 3,  21, 'CRYO_PLASMA',    1, '2027-03-03', 'QUARANTINED'),   -- 18
('VB-PLS-0008', 13, 25, 'CRYO_PLASMA',    0, '2026-12-20', 'VIABLE'),        -- 19
('VB-TIS-0004', 8,  17, 'TISSUE_CULTURE', 0, '2032-01-01', 'VIABLE'),        -- 20
('VB-TIS-0005', 9,  22, 'TISSUE_CULTURE', 2, '2029-04-18', 'VIABLE'),        -- 21
('VB-TIS-0006', 10, 23, 'TISSUE_CULTURE', 0, '2030-10-10', 'VIABLE'),        -- 22
('VB-TIS-0007', 11, 26, 'TISSUE_CULTURE', 6, '2026-09-30', 'COMPROMISED'),   -- 23
('VB-TIS-0008', 12, 28, 'TISSUE_CULTURE', 0, '2031-06-06', 'VIABLE');        -- 24

-- Donor 12 withdraws consent AFTER donating. Her existing specimens stay
-- on record (13, 24), but the trigger now blocks any NEW specimen from her.
UPDATE DONOR SET consent_status = 'WITHDRAWN' WHERE donor_id = 12;

-- Subtypes (each row must match the parent's specimen_type) -------------
INSERT INTO GENOMIC_DNA (specimen_id, concentration_ng_ul) VALUES
(1, 152.40), (2, 87.25), (3, 23.10),
(10, 210.75), (11, 64.30), (12, 118.00), (13, 175.20), (14, 41.85);

INSERT INTO CRYO_PLASMA (specimen_id, anticoagulant_type) VALUES
(4, 'EDTA'), (5, 'HEPARIN'), (6, 'CITRATE'),
(15, 'EDTA'), (16, 'ACD'), (17, 'EDTA'), (18, 'HEPARIN'), (19, 'CITRATE');

INSERT INTO TISSUE_CULTURE (specimen_id, passage_number) VALUES
(7, 3), (8, 12), (9, 27),
(20, 5), (21, 18), (22, 2), (23, 64), (24, 9);

-- RESEARCHER ------------------------------------------------------------
-- Only CLEARED researchers (1, 2, 3, 6, 7) can log custody actions.
INSERT INTO RESEARCHER (full_name, clearance_status) VALUES
('Dr. Ayesha Siddiqua', 'CLEARED'),     -- 1
('Dr. Mahmudul Hasan',  'CLEARED'),     -- 2
('Imran Chowdhury',     'CLEARED'),     -- 3
('Sadia Islam',         'PENDING'),     -- 4
('Dr. Rafiq Alam',      'SUSPENDED'),   -- 5
('Dr. Nazmul Karim',    'CLEARED'),     -- 6
('Tasfia Rahman',       'CLEARED'),     -- 7
('Rezaul Haque',        'REVOKED');     -- 8

-- CLINICAL_PROTOCOL -----------------------------------------------------
-- Only APPROVED protocols (1, 2, 5) can authorise custody actions.
INSERT INTO CLINICAL_PROTOCOL (protocol_code, approval_status) VALUES
('IRB-2026-ONC-014', 'APPROVED'),       -- 1 oncology
('IRB-2026-GEN-022', 'APPROVED'),       -- 2 genomics
('IRB-2025-CAR-007', 'EXPIRED'),        -- 3 cardiology
('IRB-2026-IMM-031', 'UNDER_REVIEW'),   -- 4 immunology
('IRB-2026-NEU-045', 'APPROVED'),       -- 5 neurology
('IRB-2024-PED-003', 'SUSPENDED');      -- 6 paediatrics

-- CUSTODY_LOG -----------------------------------------------------------
-- Every specimen has a DEPOSIT. The AFTER INSERT trigger then keeps
-- SPECIMEN.slot_id and freeze_thaw_count in step with each action.
INSERT INTO CUSTODY_LOG (specimen_id, researcher_id, protocol_id, slot_id, action_type, logged_at) VALUES
(1,  1, 2, 1,  'DEPOSIT', '2026-01-10 09:15:00'),
(2,  1, 2, 2,  'DEPOSIT', '2026-01-10 09:20:00'),
(3,  2, 2, 5,  'DEPOSIT', '2026-01-12 14:00:00'),
(4,  2, 1, 3,  'DEPOSIT', '2026-02-03 10:30:00'),
(5,  3, 1, 6,  'DEPOSIT', '2026-02-03 10:45:00'),
(6,  3, 1, 8,  'DEPOSIT', '2026-02-04 11:00:00'),
(7,  1, 1, 9,  'DEPOSIT', '2026-03-01 08:50:00'),
(8,  2, 1, 10, 'DEPOSIT', '2026-03-01 09:05:00'),
(9,  3, 1, 11, 'DEPOSIT', '2026-03-02 13:40:00'),
(10, 6, 2, 13, 'DEPOSIT', '2026-04-07 10:10:00'),
(11, 6, 2, 14, 'DEPOSIT', '2026-04-07 10:25:00'),
(12, 7, 2, 18, 'DEPOSIT', '2026-04-20 09:00:00'),
(13, 7, 5, 19, 'DEPOSIT', '2026-04-20 09:15:00'),
(14, 1, 5, 24, 'DEPOSIT', '2026-05-02 11:30:00'),
(15, 2, 1, 15, 'DEPOSIT', '2026-05-02 11:45:00'),
(16, 3, 1, 16, 'DEPOSIT', '2026-05-15 14:20:00'),
(17, 6, 5, 20, 'DEPOSIT', '2026-05-15 14:35:00'),
(18, 7, 1, 21, 'DEPOSIT', '2026-06-01 08:40:00'),
(19, 1, 5, 25, 'DEPOSIT', '2026-06-01 08:55:00'),
(20, 2, 2, 17, 'DEPOSIT', '2026-06-10 13:00:00'),
(21, 3, 5, 22, 'DEPOSIT', '2026-06-10 13:15:00'),
(22, 6, 1, 23, 'DEPOSIT', '2026-07-03 10:00:00'),
(23, 7, 5, 26, 'DEPOSIT', '2026-07-03 10:20:00'),
(24, 1, 2, 28, 'DEPOSIT', '2026-07-21 15:05:00');

-- Later activity: retrieve + return cycles, transfers, a disposal,
-- and two vials that are still checked out (22 and 21).
INSERT INTO CUSTODY_LOG (specimen_id, researcher_id, protocol_id, slot_id, action_type, logged_at) VALUES
(2,  2, 2, 2,  'RETRIEVE', '2026-06-15 10:00:00'),
(2,  2, 2, 2,  'RETURN',   '2026-06-15 16:30:00'),
(5,  1, 1, 6,  'RETRIEVE', '2026-09-20 09:00:00'),
(5,  1, 1, 7,  'RETURN',   '2026-09-20 15:10:00'),   -- returned to a different slot
(8,  3, 1, 12, 'TRANSFER', '2026-10-05 11:25:00'),
(12, 7, 2, 18, 'RETRIEVE', '2026-08-04 09:30:00'),
(12, 7, 2, 18, 'RETURN',   '2026-08-04 17:00:00'),
(14, 1, 5, 24, 'RETRIEVE', '2026-08-12 10:00:00'),
(14, 1, 5, 24, 'RETURN',   '2026-08-12 15:45:00'),
(14, 6, 5, 24, 'RETRIEVE', '2026-10-01 09:10:00'),
(14, 6, 5, 24, 'RETURN',   '2026-10-01 14:30:00'),
(17, 6, 5, 27, 'TRANSFER', '2026-09-02 11:00:00'),   -- slot 20 -> 27
(10, 2, 2, 30, 'TRANSFER', '2026-09-15 10:40:00'),   -- dewar 2: slot 13 -> 30
(16, 3, 1, 16, 'RETRIEVE', '2026-10-18 08:30:00'),
(16, 3, 1, 16, 'RETURN',   '2026-10-18 12:15:00'),
(23, 7, 5, 26, 'DISPOSE',  '2026-10-25 16:00:00'),   -- expired culture destroyed
(20, 2, 2, 17, 'RETRIEVE', '2026-11-03 09:00:00'),
(20, 2, 2, 17, 'RETURN',   '2026-11-03 13:20:00'),
(15, 6, 1, 15, 'RETRIEVE', '2026-11-10 10:05:00'),
(15, 6, 1, 15, 'RETURN',   '2026-11-10 16:40:00'),
(22, 7, 1, 23, 'RETRIEVE', '2026-11-20 09:45:00'),   -- still checked out (slot = NULL)
(21, 1, 5, 22, 'RETRIEVE', '2026-11-22 10:30:00');   -- still checked out (slot = NULL)

-- TEMPERATURE_LOG -------------------------------------------------------
-- 6-hourly readings on 1 Nov 2026 + a second day for dewars 2 and 4.
-- Excursions (above max_safe_temp_c) are marked.
INSERT INTO TEMPERATURE_LOG (dewar_id, recorded_temp_c, recorded_at) VALUES
(1, -190.50, '2026-11-01 00:00:00'),
(1, -189.80, '2026-11-01 06:00:00'),
(1, -145.20, '2026-11-01 12:00:00'),   -- excursion (above -150)
(1, -188.90, '2026-11-01 18:00:00'),
(2, -192.10, '2026-11-01 00:00:00'),
(2, -191.70, '2026-11-01 12:00:00'),
(3, -180.00, '2026-11-01 00:00:00'),
(3, -130.40, '2026-11-01 08:00:00'),   -- excursion (above -135)
(3, -128.75, '2026-11-01 09:00:00'),   -- excursion
(3, -178.60, '2026-11-01 16:00:00'),
(2, -191.90, '2026-11-15 00:00:00'),
(2, -192.30, '2026-11-15 06:00:00'),
(2, -191.40, '2026-11-15 12:00:00'),
(2, -190.80, '2026-11-15 18:00:00'),
(4, -193.50, '2026-11-01 00:00:00'),
(4, -193.20, '2026-11-01 06:00:00'),
(4, -192.80, '2026-11-01 12:00:00'),
(4, -193.00, '2026-11-01 18:00:00'),
(4, -192.60, '2026-11-15 00:00:00'),
(4, -171.40, '2026-11-15 04:00:00'),   -- warming (lid left open), still safe
(4, -148.30, '2026-11-15 05:00:00'),   -- excursion (above -150)
(4, -186.90, '2026-11-15 07:00:00'),   -- recovered after LN2 top-up
(4, -192.40, '2026-11-15 12:00:00'),
(4, -193.10, '2026-11-15 18:00:00');

-- #####################################################################
-- PART 3: STORED PROCEDURES AND TRIGGER
-- #####################################################################
-- =====================================================================
-- CSE311L FALL 2026 - Group 02
-- CryoMatrix: Cryogenic Biological Specimen Management System
-- Step 5: Stored procedures + data-integrity trigger
-- Prepared by: Tasnim Nishat (Data Integrity, QA & Documentation Lead)
--
-- Run order:  01_schema.sql  ->  02_sample_data.sql  ->  this file
-- =====================================================================
USE cryo_biobank;

DROP PROCEDURE IF EXISTS sp_register_specimen;
DROP PROCEDURE IF EXISTS sp_log_custody;
DROP PROCEDURE IF EXISTS sp_quarantine_dewar;
DROP PROCEDURE IF EXISTS sp_specimen_history;
DROP PROCEDURE IF EXISTS sp_data_integrity_report;
DROP TRIGGER   IF EXISTS trg_temperature_excursion;

DELIMITER $$

-- ---------------------------------------------------------------------
-- P1. Register a new specimen AND its subtype row in one transaction.
--     If anything fails (bad donor consent, slot taken, wrong value),
--     both inserts are rolled back, so no half-registered vial is left.
--     Pass the subtype value that matches p_type; leave the others NULL.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_register_specimen(
    IN  p_barcode        VARCHAR(30),
    IN  p_donor_id       INT,
    IN  p_slot_id        INT,
    IN  p_type           VARCHAR(20),
    IN  p_expiration     DATE,
    IN  p_concentration  DECIMAL(8,2),   -- GENOMIC_DNA only
    IN  p_anticoagulant  VARCHAR(10),    -- CRYO_PLASMA only
    IN  p_passage        SMALLINT,       -- TISSUE_CULTURE only
    OUT p_new_id         INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;                         -- show the original error message
    END;

    START TRANSACTION;

    INSERT INTO SPECIMEN (vial_barcode, donor_id, slot_id, specimen_type, expiration_date)
    VALUES (p_barcode, p_donor_id, p_slot_id, p_type, p_expiration);

    SET p_new_id = LAST_INSERT_ID();

    IF p_type = 'GENOMIC_DNA' THEN
        INSERT INTO GENOMIC_DNA (specimen_id, concentration_ng_ul) VALUES (p_new_id, p_concentration);
    ELSEIF p_type = 'CRYO_PLASMA' THEN
        INSERT INTO CRYO_PLASMA (specimen_id, anticoagulant_type) VALUES (p_new_id, p_anticoagulant);
    ELSEIF p_type = 'TISSUE_CULTURE' THEN
        INSERT INTO TISSUE_CULTURE (specimen_id, passage_number) VALUES (p_new_id, p_passage);
    END IF;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- P2. Log a custody action (DEPOSIT / RETRIEVE / RETURN / TRANSFER /
--     DISPOSE). The existing triggers check clearance + protocol and
--     update the specimen's slot and freeze-thaw count automatically.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_log_custody(
    IN p_specimen_id   INT,
    IN p_researcher_id INT,
    IN p_protocol_id   INT,
    IN p_slot_id       INT,
    IN p_action        VARCHAR(10)
)
BEGIN
    IF (SELECT quality_status FROM SPECIMEN WHERE specimen_id = p_specimen_id) = 'DISCARDED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specimen has been discarded; no further custody actions allowed.';
    END IF;

    INSERT INTO CUSTODY_LOG (specimen_id, researcher_id, protocol_id, slot_id, action_type)
    VALUES (p_specimen_id, p_researcher_id, p_protocol_id, p_slot_id, p_action);

    SELECT s.vial_barcode, s.slot_id, s.freeze_thaw_count, s.quality_status
    FROM SPECIMEN s WHERE s.specimen_id = p_specimen_id;
END$$

-- ---------------------------------------------------------------------
-- P3. Quarantine every VIABLE specimen stored in one dewar
--     (used after a thermal excursion). Returns how many were flagged.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_quarantine_dewar(
    IN  p_dewar_id INT,
    OUT p_flagged  INT
)
BEGIN
    UPDATE SPECIMEN s
    JOIN   STORAGE_SLOT ss ON ss.slot_id = s.slot_id
    SET    s.quality_status = 'QUARANTINED'
    WHERE  ss.dewar_id = p_dewar_id
      AND  s.quality_status = 'VIABLE';

    SET p_flagged = ROW_COUNT();
END$$

-- ---------------------------------------------------------------------
-- P4. Full chain-of-custody history for one vial (audit report).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_specimen_history(IN p_barcode VARCHAR(30))
BEGIN
    SELECT c.custody_id, c.logged_at, c.action_type,
           r.full_name     AS researcher,
           p.protocol_code AS protocol,
           CONCAT('D', ss.dewar_id, '/', ss.rack_code, '/', ss.cryobox_code, '/', ss.slot_code) AS slot
    FROM   CUSTODY_LOG c
    JOIN   SPECIMEN s          ON s.specimen_id   = c.specimen_id
    JOIN   RESEARCHER r        ON r.researcher_id = c.researcher_id
    JOIN   CLINICAL_PROTOCOL p ON p.protocol_id   = c.protocol_id
    JOIN   STORAGE_SLOT ss     ON ss.slot_id      = c.slot_id
    WHERE  s.vial_barcode = p_barcode
    ORDER  BY c.logged_at;
END$$

-- ---------------------------------------------------------------------
-- P5. Data-integrity (QA) report: one row per check with the number of
--     problem records found. A clean database shows 0 for checks 1-3.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_data_integrity_report()
BEGIN
    SELECT '1. Specimens with no subtype row' AS check_name,
           COUNT(*) AS problems
    FROM SPECIMEN s
    LEFT JOIN GENOMIC_DNA g    ON g.specimen_id = s.specimen_id
    LEFT JOIN CRYO_PLASMA p    ON p.specimen_id = s.specimen_id
    LEFT JOIN TISSUE_CULTURE t ON t.specimen_id = s.specimen_id
    WHERE g.specimen_id IS NULL AND p.specimen_id IS NULL AND t.specimen_id IS NULL

    UNION ALL
    SELECT '2. Specimens with no DEPOSIT in custody log',
           COUNT(*)
    FROM SPECIMEN s
    WHERE NOT EXISTS (SELECT 1 FROM CUSTODY_LOG c
                      WHERE c.specimen_id = s.specimen_id AND c.action_type = 'DEPOSIT')

    UNION ALL
    SELECT '3. Discarded specimens still occupying a slot',
           COUNT(*)
    FROM SPECIMEN WHERE quality_status = 'DISCARDED' AND slot_id IS NOT NULL

    UNION ALL
    SELECT '4. Expired specimens still marked VIABLE',
           COUNT(*)
    FROM SPECIMEN WHERE expiration_date < CURDATE() AND quality_status = 'VIABLE'

    UNION ALL
    SELECT '5. Specimens currently checked out (no slot)',
           COUNT(*)
    FROM SPECIMEN WHERE slot_id IS NULL AND quality_status <> 'DISCARDED'

    UNION ALL
    SELECT '6. Specimens with 5+ freeze-thaw cycles',
           COUNT(*)
    FROM SPECIMEN WHERE freeze_thaw_count >= 5;
END$$

-- ---------------------------------------------------------------------
-- T1. Automatic quarantine: when a temperature reading falls outside
--     the dewar's safe range, every VIABLE specimen in that dewar is
--     flagged QUARANTINED straight away.
--     (Created after the sample data, so historical readings are kept
--      as-is; it acts on every NEW reading from now on.)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_temperature_excursion
AFTER INSERT ON TEMPERATURE_LOG
FOR EACH ROW
BEGIN
    DECLARE v_min DECIMAL(6,2);
    DECLARE v_max DECIMAL(6,2);

    SELECT min_safe_temp_c, max_safe_temp_c INTO v_min, v_max
    FROM DEWAR WHERE dewar_id = NEW.dewar_id;

    IF NEW.recorded_temp_c > v_max OR NEW.recorded_temp_c < v_min THEN
        UPDATE SPECIMEN s
        JOIN   STORAGE_SLOT ss ON ss.slot_id = s.slot_id
        SET    s.quality_status = 'QUARANTINED'
        WHERE  ss.dewar_id = NEW.dewar_id
          AND  s.quality_status = 'VIABLE';
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- DEMO CALLS - run these one at a time in the review
-- =====================================================================

-- D1. QA report on the current data
-- CALL sp_data_integrity_report();

-- D2. Audit trail for one vial
-- CALL sp_specimen_history('VB-DNA-0008');

-- D3. Register a new DNA vial for donor 7 in empty slot 29 (should succeed)
-- CALL sp_register_specimen('VB-DNA-0009', 7, 29, 'GENOMIC_DNA', '2032-12-31', 98.60, NULL, NULL, @new_id);
-- SELECT @new_id;
-- CALL sp_log_custody(@new_id, 1, 2, 29, 'DEPOSIT');

-- D4. Register for donor 14 (PENDING consent) -> fails, nothing is saved
-- CALL sp_register_specimen('VB-PLS-0009', 14, 4, 'CRYO_PLASMA', '2030-01-01', NULL, 'EDTA', NULL, @new_id);

-- D5. Retrieve vial 1 for a study -> freeze-thaw count goes 0 -> 1, slot becomes NULL
-- CALL sp_log_custody(1, 1, 2, 1, 'RETRIEVE');

-- D6. Custody action on a discarded vial (23) -> fails
-- CALL sp_log_custody(23, 1, 2, 26, 'RETURN');

-- D7. New warm reading in Dewar 2 -> trigger quarantines its VIABLE vials
-- SELECT vial_barcode, quality_status FROM vw_deidentified_specimens WHERE dewar_id = 2;
-- INSERT INTO TEMPERATURE_LOG (dewar_id, recorded_temp_c) VALUES (2, -140.00);
-- SELECT vial_barcode, quality_status FROM vw_deidentified_specimens WHERE dewar_id = 2;

-- D8. Manual quarantine of Dewar 4
-- CALL sp_quarantine_dewar(4, @flagged);
-- SELECT @flagged AS specimens_quarantined;
