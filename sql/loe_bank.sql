-- loe_bank — tablolar
-- --------------------------------------------------------------------------
-- server/main.lua bu tabloları ilk başlarken `CREATE TABLE IF NOT EXISTS` ile
-- otomatik kurar; bu dosya elle kurmak / şemayı görmek isteyenler içindir.
--
-- Collation qbx `players` tablosuyla AYNI (utf8mb4_unicode_ci) olmalı; aksi
-- halde citizenid karşılaştırmaları "Illegal mix of collations" hatası verir.
-- (server/main.lua yanlış collation ile açılmış tabloları açılışta düzeltir.)

-- İŞLEM GEÇMİŞİ
--   type:         deposit | withdraw | transfer_in | transfer_out | donation
--   amount:       işlemin tutarı (her zaman pozitif; yön `type`'tan okunur)
--   balance:      işlem sonrası ilgili oyuncunun BANKA bakiyesi
--   counterparty: havalede karşı tarafın adı / hesap no'su (yoksa NULL)

CREATE TABLE IF NOT EXISTS `loe_bank_transactions` (
    `id`           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `citizenid`    VARCHAR(50)     NOT NULL,
    `type`         VARCHAR(24)     NOT NULL,
    `amount`       BIGINT          NOT NULL,
    `balance`      BIGINT          NOT NULL,
    `title`        VARCHAR(64)     NOT NULL,
    `description`  VARCHAR(160)             DEFAULT NULL,
    `counterparty` VARCHAR(64)              DEFAULT NULL,
    `created_at`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_cid_id` (`citizenid`, `id`),
    KEY `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- BANKA HESAP NUMARALARI
--   Her karaktere 4 haneli, harf+rakam, kendi içinde tekrarsız ve GLOBAL
--   benzersiz bir kod atanır (ör. K7P2). qbx charinfo.account'tan bağımsızdır.
--   account UNIQUE -> aynı kod iki kişide olamaz.

CREATE TABLE IF NOT EXISTS `loe_bank_accounts` (
    `citizenid`  VARCHAR(50) NOT NULL,
    `account`    VARCHAR(8)  NOT NULL,
    `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    UNIQUE KEY `uniq_account` (`account`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

