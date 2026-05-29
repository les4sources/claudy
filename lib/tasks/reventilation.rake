require "csv"

namespace :claudy do
  namespace :reventilation do
    # Exporte le work-list des séjours encore rattachés au Customer fourre-tout,
    # avec le contact (nom/prénom/groupe) issu de la réservation — pour alimenter
    # la passe de matching Gmail. CSV sur stdout (ou fichier via OUT=path).
    desc "Exporte les séjours du fourre-tout (contact + dates) en CSV pour le matching email"
    task export_catchall: :environment do
      catch_all = Customer.find_by(email: Customer::CATCH_ALL_EMAIL)
      abort "Aucun Customer fourre-tout (#{Customer::CATCH_ALL_EMAIL}) trouvé." if catch_all.nil?

      out = ENV["OUT"].present? ? File.open(ENV["OUT"], "w") : $stdout
      csv = CSV.new(out)
      csv << %w[stay_id first_name last_name organization_name arrival_date departure_date status origin email]
      catch_all.stays.includes(stay_items: :bookable).find_each do |stay|
        b = stay.stay_items.first&.bookable
        csv << [
          stay.id, b&.try(:firstname), b&.try(:lastname), b&.try(:group_name),
          stay.arrival_date, stay.departure_date, stay.status, stay.legacy_origin, nil
        ]
      end
      out.close unless out == $stdout
      warn "Export OK : #{catch_all.stays.count} séjours (#{ENV['OUT'] || 'stdout'})."
    end

    # Applique les correspondances validées (CSV : stay_id,email + colonnes contact
    # optionnelles). Idempotent. DRY_RUN=true pour valider sans écrire.
    desc "Applique un CSV de matchs email validés (upsert client + réassignation). CSV=path [DRY_RUN=true]"
    task apply: :environment do
      path = ENV["CSV"]
      abort "Préciser le CSV : CSV=chemin/vers/matchs.csv" if path.blank?
      abort "Fichier introuvable : #{path}" unless File.exist?(path)

      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"]).present?
      rows = CSV.read(path, headers: true).map(&:to_h)

      puts "Application de #{rows.size} ligne(s) #{dry_run ? '(DRY-RUN)' : '(RÉEL)'}…"
      applier = Reventilation::EmailMatchApplier.new(rows: rows, dry_run: dry_run)
      report = applier.run
      puts report.to_s
      exit 1 if report.n_errors.positive?
    end
  end
end
