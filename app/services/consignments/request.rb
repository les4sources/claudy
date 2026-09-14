module Consignments
  # La demande mensuelle de déclaration (epic #248, phase 2, décision 3).
  #
  # Un relevé `requested` par artisan dont le contrat court sur le mois, et un
  # email avec son lien à jeton. Pas de scheduler dans l'application : c'est
  # `rake consignment:request MONTH=2026-09` qu'on lance, en dry-run par défaut.
  #
  # IDEMPOTENT sur les deux plans. Rejouer le rake ne crée pas un second relevé
  # (l'index unique artisan + mois y veille) et ne renvoie pas un second email
  # (`requested_at` porte la trace). Un artisan sans adresse email reçoit quand
  # même son relevé — quelqu'un lui donnera le lien de la main à la main — mais
  # il est signalé.
  class Request
    Result = Struct.new(:created, :mailed, :skipped, :dry_run, keyword_init: true) do
      def to_s
        prefix = dry_run ? "simulation" : "appliqué"
        "#{prefix} — #{created.size} relevé(s) à créer, #{mailed.size} email(s) à envoyer, " \
          "#{skipped.size} artisan(s) écarté(s)"
      end
    end

    def initialize(month:, dry_run: true, resend: false)
      @month = month.beginning_of_month
      @dry_run = dry_run
      @resend = resend
    end

    def run
      created = []
      mailed = []
      skipped = []

      Consignor.actives.ordered.each do |consignor|
        unless consignor.running_on?(@month.end_of_month)
          skipped << "#{consignor.name} — contrat hors période"
          next
        end

        report = ConsignmentReport.for_month(@month).find_by(consignor_id: consignor.id)

        if report.nil?
          created << "#{consignor.name} — #{I18n.l(@month, format: '%B %Y')}"
          report = build_report(consignor) unless @dry_run
        end

        if consignor.email.blank?
          skipped << "#{consignor.name} — aucune adresse email, le lien est à donner à la main"
          next
        end

        next if report&.requested_at.present? && !@resend

        mailed << "#{consignor.name} <#{consignor.email}>"
        deliver(report) unless @dry_run
      end

      Result.new(created: created, mailed: mailed, skipped: skipped, dry_run: @dry_run)
    end

    private

    def build_report(consignor)
      ConsignmentReport.create!(consignor: consignor, period_month: @month, status: "requested")
    end

    def deliver(report)
      return if report.blank?

      ConsignmentMailer.monthly_request(report).deliver_later
      report.update_column(:requested_at, Time.current)
    end
  end
end
