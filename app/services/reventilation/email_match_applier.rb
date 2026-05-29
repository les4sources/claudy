module Reventilation
  # Applique des correspondances séjour → email (validées à la main après une
  # passe de matching Gmail) : pour chaque ligne, upsert le Customer par email
  # puis réassigne le séjour depuis le fourre-tout vers ce client, via le même
  # MergeService que la fusion/re-ventilation manuelle.
  #
  # Sûr et idempotent :
  #   - un séjour qui n'est PLUS sur le fourre-tout (déjà re-ventilé) est ignoré ;
  #   - l'upsert par email ne crée jamais de doublon ;
  #   - tout est tracé PaperTrail sous whodunnit "system:reventilation-match".
  #
  # Une ligne = un Hash :
  #   { stay_id:, email:, first_name:, last_name:, organization_name:, customer_type:, phone: }
  # Seuls stay_id + email sont requis ; le reste enrichit un client créé.
  class EmailMatchApplier < ServiceBase
    WHODUNNIT = "system:reventilation-match".freeze

    Report = Struct.new(
      :dry_run, :n_applied, :n_created_customers, :n_skipped_not_catch_all,
      :n_errors, :errors,
      keyword_init: true
    ) do
      def to_s
        lines = ["=== Application matching email → séjour #{dry_run ? '(DRY RUN)' : '(RÉEL)'} ==="]
        lines << "Réassignés          : #{n_applied}"
        lines << "Clients créés       : #{n_created_customers}"
        lines << "Ignorés (hors fourre-tout / déjà fait) : #{n_skipped_not_catch_all}"
        lines << "Erreurs             : #{n_errors}"
        errors.each { |e| lines << "  - #{e}" }
        lines.join("\n")
      end
    end

    def initialize(rows:, dry_run: false)
      @rows = rows
      @dry_run = dry_run
      @report = Report.new(
        dry_run: dry_run, n_applied: 0, n_created_customers: 0,
        n_skipped_not_catch_all: 0, n_errors: 0, errors: []
      )
    end

    attr_reader :report

    def run
      PaperTrail.request(whodunnit: WHODUNNIT) do
        @rows.each { |row| apply_row(row.symbolize_keys) }
      end
      @report
    end

    private

    def catch_all
      @catch_all ||= Customer.find_by(email: Customer::CATCH_ALL_EMAIL)
    end

    def apply_row(row)
      stay = Stay.find_by(id: row[:stay_id])
      return record_error("stay #{row[:stay_id]} introuvable") if stay.nil?

      # Idempotence : on ne touche QUE les séjours encore rattachés au fourre-tout.
      if catch_all.nil? || stay.customer_id != catch_all.id
        @report.n_skipped_not_catch_all += 1
        return
      end

      email = Customer.normalize_email(row[:email])
      return record_error("stay #{row[:stay_id]} : email invalide (#{row[:email].inspect})") unless Customer.exploitable_email?(email)

      return if @dry_run # dry-run : on a validé que la ligne est applicable, on n'écrit rien

      target = upsert_customer(email, row)
      service = Customers::MergeService.new(source: catch_all, target: target)
      if service.run(stay_ids: [stay.id])
        @report.n_applied += 1
      else
        record_error("stay #{row[:stay_id]} : échec merge (#{service.error_message})")
      end
    end

    def upsert_customer(email, row)
      existing = Customer.unscoped.find_by(email: email)
      return existing if existing

      customer = Customer.new(
        email: email,
        first_name: row[:first_name].presence,
        last_name: row[:last_name].presence,
        phone: row[:phone].presence,
        organization_name: row[:organization_name].presence,
        customer_type: row[:customer_type].presence || (row[:organization_name].presence ? "organization" : "individual")
      )
      customer.save!(validate: false) # données legacy partielles ; la clé est l'email
      @report.n_created_customers += 1
      customer
    end

    def record_error(message)
      @report.n_errors += 1
      @report.errors << message
    end
  end
end
