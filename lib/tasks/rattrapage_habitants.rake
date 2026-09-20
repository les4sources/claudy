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

  # Le « Forfait fun et découverte » : 2 540 € facturés de janvier 2023 à juin
  # 2024 et réputés impayés. Les foyers les ont pourtant bien versés — mais
  # DANS LEUR VIREMENT MENSUEL, ce que la comparaison mois par mois démontre :
  # Gaëlle payait 260 € là où claudy facture 200, Olivier 400 là où claudy
  # facture 310, et l'excédent cumulé vaut EXACTEMENT le forfait facturé
  # (870,00 € et 930,00 €, au centime). La reprise a imputé tout le virement aux
  # charges ; d'où un forfait impayé d'un côté et une avance sur charges de
  # l'autre, pour le même argent.
  #
  # On ne crée donc PAS de règlement supplémentaire — ce serait compter deux
  # fois. On redécoupe le virement mensuel, comme pour le dôme de Seb : la part
  # du forfait quitte les charges pour « Divers ». Le solde du compte ne bouge
  # pas d'un centime, seule la ventilation change.
  #
  # Vérifié sur les trois : le virement mensuel valait charges + dôme + forfait,
  # au centime (Seb versait 310 € pour 200 de charges, 50 de dôme et 60 de
  # forfait). Les virements « fun et découvertes » qu'on voit à côté sur le
  # Triodos — trimestres, soldes annuels, clôture — ne sont donc PAS ce forfait
  # mensuel : ils paient les sorties elles-mêmes, que claudy ne facture nulle
  # part. Les encoder ici mettrait les comptes en faux crédit.
  #
  # Chez Michael & Malau, rien n'était facturé alors que 93,34 € ont été versés
  # à part : on pose les deux charges manquantes à la date du service.
  FORFAIT_LABEL = "Forfait fun et découverte".freeze

  # Ce qui n'est PAS passé par le virement mensuel, et se règle à part.
  FORFAIT_REGLEMENTS = [
    ["SRC-0001", "2024-03-06", 2_579,  "Forfait fun et découverte 2023 — Mael"],
    ["SRC-0001", "2025-04-04", 6_755,  "Forfait fun et découverte 2024"]
  ].freeze

  FORFAIT_CHARGES = [
    ["SRC-0001", "2023-12-31", 2_579],
    ["SRC-0001", "2024-12-31", 6_755]
  ].freeze

  desc "Le forfait fun et découverte : sort du virement mensuel où il était noyé. APPLY=1 pour écrire."
  task forfait: :environment do
    apply = ENV["APPLY"] == "1"

    FORFAIT_CHARGES.each do |code, date, cents|
      compte = MemberAccount.find_by!(code: code)
      cle = "rattrapage:forfait:#{code}:#{date}"
      next puts("  = #{date}  #{code}  charge déjà présente") if AccountEntry.unscoped.exists?(idempotency_key: cle)

      puts "  + #{date}  #{code}  #{FORFAIT_LABEL.ljust(28)} #{format('%8.2f', cents / 100.0)} € (charge)"
      next unless apply

      PaperTrail.request(whodunnit: "rattrapage-2026-09") do
        AccountEntry.create!(member_account: compte, entry_date: Date.parse(date), posted_at: Time.current,
                             amount_cents: cents, flow: "other", kind: "recurring",
                             label: FORFAIT_LABEL, source: "reprise", idempotency_key: cle)
      end
    end

    MemberAccount.actives.ordered.each do |compte|
      forfaits = compte.account_entries.where(label: FORFAIT_LABEL).where("amount_cents > 0")
                       .group_by { |e| e.entry_date.beginning_of_month }
                       .transform_values { |lignes| lignes.sum(&:amount_cents) }
      next if forfaits.empty?

      reglements = compte.account_settlements
                         .where("reference LIKE 'reprise-charges%' OR reference LIKE '%charges-habitants'")
                         .index_by { |s| s.received_on.beginning_of_month }
      sorti = 0

      forfaits.sort.each do |mois, du_forfait|
        settlement = reglements[mois]
        next if settlement.nil?

        ventilation = settlement.account_entries.group_by(&:flow)
                                .transform_values { |lignes| lignes.sum(&:amount_cents).abs }
        deja = ventilation["other"].to_i
        next sorti += deja if deja.positive?

        # L'excédent du virement sur les charges du mois : c'est LUI qui payait
        # le forfait. On n'en sort jamais plus que ce que le forfait réclamait.
        facture = compte.account_entries.where(flow: %w[charges dome])
                        .where(entry_date: mois..mois.end_of_month).where("amount_cents > 0").sum(:amount_cents)
        part = [settlement.amount_cents - facture, du_forfait].min
        next unless part.positive?

        sorti += part
        nouvelle = ventilation.dup
        nouvelle["charges"] = nouvelle["charges"].to_i - part
        nouvelle["other"] = part
        puts "  ~ #{mois.strftime('%Y-%m')}  #{compte.code}  #{format('%6.2f', part / 100.0)} € sortis des charges vers Divers (règlement ##{settlement.id})"
        next unless apply

        Finance::ReventilateSettlement.new(settlement: settlement, ventilation: nouvelle.reject { |_, c| c.zero? },
                                           whodunnit: "rattrapage-2026-09").run!
      end

      reste = forfaits.values.sum - sorti
      puts "  → #{compte.code} #{compte.name.ljust(18)} forfait #{format('%8.2f', forfaits.values.sum / 100.0)} € · sorti du mensuel #{format('%8.2f', sorti / 100.0)} € · reste #{format('%8.2f', reste / 100.0)} €"
    end

    # La référence ne porte PAS l'indice dans la liste : retirer une ligne
    # décalerait tous les indices suivants, la garde ne reconnaîtrait plus rien
    # et la tâche créerait des doublons. Elle est faite de ce qui identifie le
    # virement — le compte, la date, le montant.
    FORFAIT_REGLEMENTS.each do |code, date, cents, motif|
      compte = MemberAccount.find_by!(code: code)
      reference = "forfait-fun:#{code}:#{date}:#{cents}"
      next puts("  = #{date}  #{code}  règlement déjà encodé") if AccountSettlement.unscoped.exists?(reference: reference)

      puts "  + #{date}  #{code}  #{motif[0, 42].ljust(42)} #{format('%8.2f', cents / 100.0)} € (règlement)"
      next unless apply

      Finance::RecordSettlement.new(
        member_account: compte, amount_cents: cents, received_on: Date.parse(date),
        method: "bank_transfer", received_channel: "bank", reference: reference, flow: "other",
        notes: "#{motif}. Rattrapage du 2026-09-20 : la reprise avait transcrit la facturation sans les paiements.",
        whodunnit: "rattrapage-2026-09"
      ).run!
    end

    puts "[rattrapage:forfait] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Les quatre rattrapages, dans l'ordre. APPLY=1 pour écrire."
  task tout: %i[charges reglements dome_seb forfait]
end
