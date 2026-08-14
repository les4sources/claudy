# Construit les fixtures CODA en plaçant chaque champ à sa position, typée
# depuis docs/coda-layout.md — indépendamment du parseur, pour que les deux ne
# partagent pas une même erreur de décalage.
DIR = "/Users/michael/code/claudy/spec/fixtures/coda"

def blank_record = " " * 128

def put(record, from, value)
  record = record.dup
  record[from - 1, value.length] = value
  record
end

def amount(euros) # 15 car., 12 entiers + 3 décimales
  format("%015d", (euros * 1000).round)
end

def account_zone(iban) = iban.ljust(34) + "EUR"

def header(date: "150826", reference: "TESTFILE01", addressee: "LES 4 SOURCES")
  r = blank_record
  r = put(r, 1, "0")
  r = put(r, 2, "0000")
  r = put(r, 6, date)
  r = put(r, 12, "000")
  r = put(r, 15, "05")
  r = put(r, 25, reference.ljust(10))
  r = put(r, 35, addressee.ljust(26))
  r = put(r, 61, "TRIOBEBB   ")
  r = put(r, 72, "00000000000")
  r = put(r, 84, "00000")
  put(r, 128, "2")
end

def old_balance(iban:, sequence:, balance:, date:, name: "FONDATION 4 SOURCES", paper: "001")
  r = blank_record
  r = put(r, 1, "1")
  r = put(r, 2, "2") # IBAN belge
  r = put(r, 3, paper)
  r = put(r, 6, account_zone(iban))
  r = put(r, 43, balance.negative? ? "1" : "0")
  r = put(r, 44, amount(balance.abs))
  r = put(r, 59, date)
  r = put(r, 65, name.ljust(26))
  r = put(r, 91, "COMPTE COURANT".ljust(35))
  put(r, 126, sequence)
end

def movement(seq:, amount_eur:, value_date:, entry_date:, communication:, structured: false,
             detail: "0000", code: "01500000", next_code: "0", link: "0", bank_ref: "REF#{seq}")
  r = blank_record
  r = put(r, 1, "2")
  r = put(r, 2, "1")
  r = put(r, 3, seq)
  r = put(r, 7, detail)
  r = put(r, 11, bank_ref.ljust(21))
  r = put(r, 32, amount_eur.negative? ? "1" : "0")
  r = put(r, 33, amount(amount_eur.abs))
  r = put(r, 48, value_date)
  r = put(r, 54, code)
  r = put(r, 62, structured ? "1" : "0")
  r = put(r, 63, communication.ljust(53))
  r = put(r, 116, entry_date)
  r = put(r, 122, "001")
  r = put(r, 125, "0")
  r = put(r, 126, next_code)
  put(r, 128, link)
end

def movement_2_2(seq:, detail: "0000", communication: "", customer_ref: "", bic: "", next_code: "1", link: "0")
  r = blank_record
  r = put(r, 1, "2")
  r = put(r, 2, "2")
  r = put(r, 3, seq)
  r = put(r, 7, detail)
  r = put(r, 11, communication.ljust(53))
  r = put(r, 64, customer_ref.ljust(35))
  r = put(r, 99, bic.ljust(11))
  r = put(r, 126, next_code)
  put(r, 128, link)
end

def movement_2_3(seq:, detail: "0000", account: "", name: "", communication: "", link: "0")
  r = blank_record
  r = put(r, 1, "2")
  r = put(r, 2, "3")
  r = put(r, 3, seq)
  r = put(r, 7, detail)
  r = put(r, 11, account_zone(account))
  r = put(r, 48, name.ljust(35))
  r = put(r, 83, communication.ljust(43))
  r = put(r, 126, "0")
  put(r, 128, link)
end

def information(seq:, detail: "0000", text:, bank_ref: "REF#{seq}", code: "01500000", structured: false)
  r = blank_record
  r = put(r, 1, "3")
  r = put(r, 2, "1")
  r = put(r, 3, seq)
  r = put(r, 7, detail)
  r = put(r, 11, bank_ref.ljust(21))
  r = put(r, 32, code)
  r = put(r, 40, structured ? "1" : "0")
  r = put(r, 41, text.ljust(73))
  r = put(r, 126, "0")
  put(r, 128, "0")
end

def new_balance(iban:, balance:, date:, paper: "001")
  r = blank_record
  r = put(r, 1, "8")
  r = put(r, 2, paper)
  r = put(r, 5, account_zone(iban))
  r = put(r, 42, balance.negative? ? "1" : "0")
  r = put(r, 43, amount(balance.abs))
  r = put(r, 58, date)
  put(r, 128, "0")
end

def trailer(records:, debit:, credit:)
  r = blank_record
  r = put(r, 1, "9")
  r = put(r, 17, format("%06d", records))
  r = put(r, 23, amount(debit))
  r = put(r, 38, amount(credit))
  put(r, 128, "2")
end

IBAN = "BE55068000000000"
IBAN2 = "BE77068011111111"

# 1 — nominal : 1000 + 1300 - 450 = 1850
nominal = [
  header,
  old_balance(iban: IBAN, sequence: "001", balance: 1000.0, date: "310726"),
  movement(seq: "0001", amount_eur: 1300.0, value_date: "120826", entry_date: "120826",
           communication: "VIREMENT GROUPE DUPONT SEJOUR AOUT", link: "1"),
  information(seq: "0001", text: "PAIEMENT SEJOUR 12 AU 15 AOUT"),
  movement(seq: "0002", amount_eur: -450.0, value_date: "130826", entry_date: "130826",
           communication: "FACTURE BRICO YVOIR"),
  new_balance(iban: IBAN, balance: 1850.0, date: "130826"),
  trailer(records: 4, debit: 450.0, credit: 1300.0)
]
File.write(File.join(DIR, "nominal.cod"), nominal.join("\n") + "\n")

# 2 — écart intra-relevé : le nouveau solde ne colle pas
ecart = [
  header,
  old_balance(iban: IBAN, sequence: "001", balance: 1000.0, date: "310726"),
  movement(seq: "0001", amount_eur: 1300.0, value_date: "120826", entry_date: "120826",
           communication: "VIREMENT GROUPE DUPONT"),
  new_balance(iban: IBAN, balance: 9999.0, date: "120826"),
  trailer(records: 3, debit: 0.0, credit: 1300.0)
]
File.write(File.join(DIR, "ecart_intra.cod"), ecart.join("\n") + "\n")

# 3 — rupture de chaînage entre deux relevés du même compte
rupture = [
  header,
  old_balance(iban: IBAN, sequence: "001", balance: 1000.0, date: "310726"),
  movement(seq: "0001", amount_eur: 500.0, value_date: "010826", entry_date: "010826",
           communication: "PREMIER MOUVEMENT"),
  new_balance(iban: IBAN, balance: 1500.0, date: "010826"),
  old_balance(iban: IBAN, sequence: "002", balance: 7777.0, date: "010826", paper: "002"),
  movement(seq: "0001", amount_eur: 100.0, value_date: "050826", entry_date: "050826",
           communication: "DEUXIEME MOUVEMENT"),
  new_balance(iban: IBAN, balance: 7877.0, date: "050826", paper: "002"),
  trailer(records: 6, debit: 0.0, credit: 600.0)
]
File.write(File.join(DIR, "rupture_chainage.cod"), rupture.join("\n") + "\n")

# 4 — deux relevés valides, deux comptes différents
multi = [
  header,
  old_balance(iban: IBAN, sequence: "001", balance: 1000.0, date: "310726"),
  movement(seq: "0001", amount_eur: 250.0, value_date: "020826", entry_date: "020826",
           communication: "DON RECU"),
  new_balance(iban: IBAN, balance: 1250.0, date: "020826"),
  old_balance(iban: IBAN2, sequence: "001", balance: 300.0, date: "310726", paper: "002"),
  movement(seq: "0001", amount_eur: -75.5, value_date: "030826", entry_date: "030826",
           communication: "FRAIS BANCAIRES"),
  new_balance(iban: IBAN2, balance: 224.5, date: "030826", paper: "002"),
  trailer(records: 6, debit: 75.5, credit: 250.0)
]
File.write(File.join(DIR, "multi_releves.cod"), multi.join("\n") + "\n")

# 5 — communication structurée et contrepartie complète
structure = [
  header,
  old_balance(iban: IBAN, sequence: "001", balance: 0.0, date: "310726"),
  movement(seq: "0001", amount_eur: 820.0, value_date: "100826", entry_date: "100826",
           communication: "101" + "123456789012345", structured: true, next_code: "1", link: "0"),
  movement_2_2(seq: "0001", communication: "SUITE COMMUNICATION", customer_ref: "REFCLIENT99", bic: "GEBABEBB"),
  movement_2_3(seq: "0001", account: "BE62510007547061", name: "ASSOCIATION DUPONT"),
  new_balance(iban: IBAN, balance: 820.0, date: "100826"),
  trailer(records: 5, debit: 0.0, credit: 820.0)
]
File.write(File.join(DIR, "structuree.cod"), structure.join("\n") + "\n")

# 6 — continuité applicative : relevé 002 dont l'ancien solde ne suit pas le
# nouveau solde du relevé 001 (importé précédemment depuis nominal.cod : 1850)
trou = [
  header(reference: "TESTFILE03"),
  old_balance(iban: IBAN, sequence: "002", balance: 9999.0, date: "130826", paper: "002"),
  movement(seq: "0001", amount_eur: 1.0, value_date: "200826", entry_date: "200826",
           communication: "MOUVEMENT APRES LE TROU"),
  new_balance(iban: IBAN, balance: 10_000.0, date: "200826", paper: "002"),
  trailer(records: 3, debit: 0.0, credit: 1.0)
]
File.write(File.join(DIR, "trou_continuite.cod"), trou.join("\n") + "\n")

puts Dir[File.join(DIR, "*.cod")].map { |f| "#{File.basename(f)}: #{File.readlines(f).map(&:chomp).map(&:length).uniq.inspect}" }
