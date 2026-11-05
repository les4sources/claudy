namespace :paper_sheets do
  # Rattache à la fiche papier d'un mois les écritures posées sans elle (cas de
  # la feuille de bar d'octobre 2026, encodée ligne par ligne par le
  # connecteur). Ne change aucun montant. Voir Finance::AttachEntriesToPaperSheet.
  #
  #   bundle exec rake paper_sheets:rattacher MOIS=2026-10           # essai à blanc
  #   APPLY=1 bundle exec rake paper_sheets:rattacher MOIS=2026-10   # écrit
  desc "Rattache à la fiche papier du mois les écritures posées sans elle (MOIS=AAAA-MM, CANAL=bar). APPLY=1 pour écrire."
  task rattacher: :environment do
    month = ENV.fetch("MOIS") { abort "Donne le mois : MOIS=AAAA-MM" }
    channel = ENV.fetch("CANAL", "bar")
    apply = ENV["APPLY"] == "1"
    euros = ->(cents) { format("%.2f €", cents / 100.0).tr(".", ",") }

    report = Finance::AttachEntriesToPaperSheet.new(
      month: Date.parse("#{month}-01"), channel: channel, apply: apply, whodunnit: "rake:paper_sheets:rattacher"
    ).run

    sheet = report.sheet
    puts apply ? "== APPLICATION ==" : "== ESSAI À BLANC (APPLY=1 pour écrire) =="
    puts "Fiche #{channel} #{month} : #{sheet.persisted? ? "##{sheet.id}" : 'à créer'}"
    puts

    report.attached.group_by { |line| line.entry.member_account }.each do |account, lines|
      puts "#{account.code} — #{account.name} : #{lines.size} ligne(s), #{euros.call(lines.sum { |l| l.entry.amount_cents })}"
      lines.each do |line|
        quantity = line.quantity ? "× #{line.quantity.to_s.sub(/\.0\z/, '')}" : "(quantité inconnue)"
        lock = line.entry.locked? ? " [verrouillée]" : ""
        puts "  ##{line.entry.id}  #{line.entry.entry_date}  #{euros.call(line.entry.amount_cents).rjust(10)}  " \
             "#{line.entry.label} → #{line.item.name} #{quantity}#{lock}"
      end
    end

    puts
    puts "À rattacher : #{report.attached.size + report.unmatched.size} écriture(s), #{euros.call(report.total_cents)}"

    if report.unmatched.any?
      puts "\nHors catalogue (rattachées aussi, comptées dans le total, sans case dans la matrice) :"
      report.unmatched.each do |line|
        puts "  ##{line.entry.id}  #{line.entry.member_account.code}  #{euros.call(line.entry.amount_cents)}  #{line.entry.label} — #{line.reason}"
      end
    end

    if report.conflicts.any?
      puts "\nEn conflit (laissées telles quelles) :"
      report.conflicts.each do |line|
        puts "  ##{line.entry.id}  #{line.entry.member_account.code}  #{line.entry.label} — #{line.reason}"
      end
    end

    puts "\nFait : fiche ##{report.sheet.id}, #{report.sheet.account_entries.count} écriture(s), #{euros.call(report.sheet.total_cents)}." if report.applied
  end
end
