# Rattrapage ponctuel des comptes des foyers — audit du 2026-09-19/20.
#
# Trois corrections, à jouer une fois, dans cet ordre. Chacune est un dry-run
# par défaut et s'écrit avec APPLY=1, chacune est idempotente : rejouer ne
# double rien. Ces tâches documentent une correction datée — elles ne sont pas
# faites pour resservir, et pourront être retirées une fois passées en prod.
#
# Ce qu'elles réparent : 2 888 € de virements Triodos reçus et jamais encodés
# (dont les 75 €/mois de Béné, versés tous les mois depuis janvier), 300,80 € de
# poulets de novembre 2025, les charges d'août et septembre jamais générées, et
# le dôme de Seb — 2 100 € payés dans son virement mensuel mais imputés en
# totalité aux charges par la reprise.
namespace :rattrapage do
  CHARGES_MENSUELLES = {
    "SRC-0001" => [["Charges habitants", 34_500, "charges"]],
    "SRC-0002" => [["Charges habitants", 31_000, "charges"]],
    "SRC-0003" => [["Charges habitants", 28_000, "charges"]],
    "SRC-0004" => [["Charges habitants", 20_500, "charges"]],
    "SRC-0005" => [["Charges habitants", 7_500, "charges"], ["Loyer", 35_000, "charges"]]
  }.freeze

  # Chaque ligne est un virement CONSTATÉ sur l'extrait Triodos et jamais
  # encodé. Le poste est celui que le virement éteint — c'est lui qui permet au
  # lettrage de rendre la bonne dette. Les virements sans charge en face
  # (Repas Aya, stage low tech, épicerie, pain, cagnotte, pension d'animaux)
  # sont volontairement absents : les encoder mettrait le compte en faux crédit.
  REGLEMENTS = [
    ["SRC-0001", "2026-02-04", 4_500,  "charges", "Supplément charges février 2026"],
    ["SRC-0001", "2026-08-31", 34_500, "charges", "Charges du mois"],
    ["SRC-0002", "2026-08-11", 31_000, "charges", "Participation famille Vanhamme"],
    ["SRC-0003", "2026-08-11", 28_000, "charges", "Participation famille Frennet"],
    ["SRC-0003", "2026-07-31", 12_406, "bar",     "Bar juin 2026"],
    ["SRC-0003", "2026-08-27", 1_400,  "bar",     "Bar"],
    ["SRC-0004", "2026-08-06", 20_500, "charges", "Charges août 2026"],
    ["SRC-0004", "2026-09-01", 20_500, "charges", "Charges septembre 2026"],
    ["SRC-0005", "2026-01-05", 6_000,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-02-03", 6_000,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-02-10", 1_000,  "charges", "Solde frais février 2026"],
    ["SRC-0005", "2026-02-10", 500,    "charges", "Solde frais février 2026 (complément)"],
    ["SRC-0005", "2026-03-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-04-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-05-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-06-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-07-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-08-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-09-03", 7_500,  "charges", "Frais mensuels"],
    ["SRC-0005", "2026-08-03", 35_000, "charges", "Loyer"],
    ["SRC-0005", "2026-09-03", 35_000, "charges", "Loyer"],
    # Les poulets de novembre 2025 : six ménages facturés, cinq virements
    # retrouvés, zéro règlement encodé. Seul le second lot de Seb (92,17 €)
    # n'a pas de virement en face — il reste dû.
    ["SRC-0002", "2025-11-26", 9_070,  "grocery", "Vente de poulets"],
    ["SRC-0005", "2025-11-29", 4_000,  "grocery", "Vente de poulets"],
    ["SRC-0003", "2026-01-08", 8_548,  "grocery", "Vente de poulets"],
    ["SRC-0004", "2026-01-14", 4_032,  "grocery", "Vente de poulets"],
    ["SRC-0001", "2026-02-04", 4_430,  "grocery", "Vente de poulets"]
  ].freeze

  desc "Charges d'août et septembre 2026, calquées sur juillet. APPLY=1 pour écrire."
  task charges: :environment do
    apply = ENV["APPLY"] == "1"
    total = 0

    %w[2026-08 2026-09].each do |mois|
      fin = Date.parse("#{mois}-01").end_of_month
      CHARGES_MENSUELLES.each do |code, lignes|
        compte = MemberAccount.find_by!(code: code)
        lignes.each do |label, cents, flow|
          cle = "rattrapage:#{mois}:#{code}:#{label.parameterize}"
          next puts("  = #{fin}  #{code}  #{label.ljust(20)} déjà présente") if AccountEntry.unscoped.exists?(idempotency_key: cle)

          total += cents
          puts "  + #{fin}  #{code}  #{label.ljust(20)} #{format('%8.2f', cents / 100.0)} €"
          next unless apply

          PaperTrail.request(whodunnit: "rattrapage-2026-09") do
            AccountEntry.create!(member_account: compte, entry_date: fin, posted_at: Time.current,
                                 amount_cents: cents, flow: flow, kind: "recurring",
                                 label: label, source: "reprise", idempotency_key: cle)
          end
        end
      end
    end

    puts "[rattrapage:charges] #{format('%.2f', total / 100.0)} € de charges"
    puts "[rattrapage:charges] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Règlements Triodos constatés et jamais encodés. APPLY=1 pour écrire."
  task reglements: :environment do
    apply = ENV["APPLY"] == "1"
    total = 0

    REGLEMENTS.each_with_index do |(code, date, cents, flow, motif), index|
      compte = MemberAccount.find_by!(code: code)
      reference = "triodos-2026:#{code}:#{date}:#{index}"
      next puts("  = #{date}  #{code}  #{motif.ljust(38)} déjà encodé") if AccountSettlement.unscoped.exists?(reference: reference)

      total += cents
      puts "  + #{date}  #{code}  #{motif.ljust(38)} #{format('%8.2f', cents / 100.0)} € → #{AccountEntry::FLOW_LABELS.fetch(flow, flow)}"
      next unless apply

      Finance::RecordSettlement.new(
        member_account: compte, amount_cents: cents, received_on: Date.parse(date),
        method: "bank_transfer", received_channel: "bank", reference: reference, flow: flow,
        notes: "#{motif} — virement Triodos non encodé, rattrapage du 2026-09-19.",
        whodunnit: "rattrapage-2026-09"
      ).run!
    end

    puts "[rattrapage:reglements] #{format('%.2f', total / 100.0)} € de règlements"
    puts "[rattrapage:reglements] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Le dôme de Seb : redécoupe ses règlements de charges en charges + 50 € de dôme. APPLY=1 pour écrire."
  task dome_seb: :environment do
    apply = ENV["APPLY"] == "1"
    compte = MemberAccount.find_by!(code: "SRC-0003")
    dome = 5_000

    mois_dome = compte.account_entries.where(flow: "dome").where("amount_cents > 0")
                      .map { |e| e.entry_date.beginning_of_month }.uniq
    reglements = compte.account_settlements
                       .where("reference LIKE 'reprise-charges%' OR reference LIKE '%charges-habitants'")
                       .index_by { |s| s.received_on.beginning_of_month }

    traites = 0
    manquants = []

    mois_dome.sort.each do |mois|
      settlement = reglements[mois]
      next manquants << mois if settlement.nil?
      next puts("  = #{mois.strftime('%Y-%m')}  règlement ##{settlement.id} déjà ventilé") if settlement.account_entries.any? { |e| e.flow == "dome" }

      charges = settlement.amount_cents - dome
      next manquants << mois if charges <= 0

      traites += 1
      puts "  + #{mois.strftime('%Y-%m')}  ##{settlement.id} de #{format('%6.2f', settlement.amount_cents / 100.0)} € → charges #{format('%6.2f', charges / 100.0)} + dôme #{format('%5.2f', dome / 100.0)}"
      next unless apply

      Finance::ReventilateSettlement.new(
        settlement: settlement, ventilation: { "charges" => charges, "dome" => dome },
        whodunnit: "rattrapage-2026-09"
      ).run!
    end

    puts "[rattrapage:dome_seb] #{traites} règlement(s), #{format('%.2f', dome * traites / 100.0)} € basculés sur le dôme"
    puts "[rattrapage:dome_seb] ! #{manquants.size} mois sans règlement de charges en face : #{manquants.map { |m| m.strftime('%Y-%m') }.join(', ')}" if manquants.any?
    puts "[rattrapage:dome_seb] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Les trois rattrapages, dans l'ordre. APPLY=1 pour écrire."
  task tout: %i[charges reglements dome_seb]
end
