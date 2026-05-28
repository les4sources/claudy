module LegacyBookingMigration
  # One-shot, idempotent migration of every legacy Booking + SpaceBooking onto
  # the Customer / Stay / StayItem graph.
  #
  # Invariants (PRD §3.3, AC-33..49):
  #   - Reads the source rows; NEVER mutates a Booking or SpaceBooking (zero data
  #     loss is structural — only Customer/Stay/StayItem rows are created).
  #   - Covers the WHOLE history: active, past, canceled AND soft-deleted
  #     (enumerated via `with_deleted`).
  #   - Idempotent: the StayItem unique index + Stay.legacy_origin marker mean a
  #     second run creates nothing new (same counts).
  #   - Bookings without an exploitable email (blank or format-invalid) are
  #     attached to the single catch-all Customer client@les4sources.be — never
  #     skipped. A format-valid OTA address gets its own Customer.
  #   - Stay creation is attributed to whodunnit "system:migration".
  #   - PaperTrail + PublicActivity on the source rows are untouched (we never
  #     write to them), so both audit trails are preserved.
  class Runner < ServiceBase
    WHODUNNIT = "system:migration".freeze

    Report = Struct.new(
      :dry_run,
      :n_stays_created, :n_customers_created, :n_customers_upserted,
      :n_actifs, :n_passes, :n_annules, :n_soft_deleted, :n_rattaches_fourretout,
      :n_already_migrated, :n_bookings_seen, :n_space_bookings_seen,
      keyword_init: true
    ) do
      def to_h_report
        to_h
      end

      def to_s
        lines = []
        lines << "=== Rapport migration legacy -> stays #{dry_run ? '(DRY RUN — aucune écriture)' : '(RÉEL)'} ==="
        lines << "Bookings vus            : #{n_bookings_seen}"
        lines << "SpaceBookings vus       : #{n_space_bookings_seen}"
        lines << "Stays créés             : #{n_stays_created}"
        lines << "Déjà migrés (skip)      : #{n_already_migrated}"
        lines << "Customers créés         : #{n_customers_created}"
        lines << "Customers upsertés      : #{n_customers_upserted}"
        lines << "--- ventilation booking ---"
        lines << "  actifs (à venir)      : #{n_actifs}"
        lines << "  passés                : #{n_passes}"
        lines << "  annulés               : #{n_annules}"
        lines << "  soft-deleted          : #{n_soft_deleted}"
        lines << "  rattachés fourre-tout : #{n_rattaches_fourretout}"
        lines.join("\n")
      end
    end

    def initialize(dry_run: false, logger: nil)
      @dry_run = dry_run
      @logger = logger
      @report = Report.new(
        dry_run: dry_run,
        n_stays_created: 0, n_customers_created: 0, n_customers_upserted: 0,
        n_actifs: 0, n_passes: 0, n_annules: 0, n_soft_deleted: 0,
        n_rattaches_fourretout: 0, n_already_migrated: 0,
        n_bookings_seen: 0, n_space_bookings_seen: 0
      )
      # In-run cache of email -> customer so two bookings with the same email in
      # the same run don't double-count an upsert.
      @customer_cache = {}
    end

    attr_reader :report

    def run
      PaperTrail.request(whodunnit: WHODUNNIT) do
        Booking.with_deleted do
          Booking.unscoped.find_each do |booking|
            @report.n_bookings_seen += 1
            migrate_record(booking)
          end
        end
        SpaceBooking.with_deleted do
          SpaceBooking.unscoped.find_each do |space_booking|
            @report.n_space_bookings_seen += 1
            migrate_record(space_booking)
          end
        end
      end
      @report
    end

    private

    def migrate_record(record)
      origin = "#{record.class.name}##{record.id}"

      # Idempotency: if a Stay already exists for this source, do nothing.
      if Stay.unscoped.where(legacy_origin: origin).exists?
        @report.n_already_migrated += 1
        return
      end

      tally_category(record)

      return if @dry_run # dry-run: count only, write nothing (AC-33)

      customer = upsert_customer_for(record)
      stay = Stay.create!(
        customer: customer,
        arrival_date: record.from_date,
        departure_date: record.to_date,
        status: record.status,
        total_amount_cents: record.try(:price_cents).to_i,
        legacy_origin: origin
      )
      StayItem.create!(stay: stay, bookable_type: record.class.name, bookable_id: record.id)
      @report.n_stays_created += 1
    end

    def tally_category(record)
      if record.deleted_at.present?
        @report.n_soft_deleted += 1
      elsif record.status == "canceled"
        @report.n_annules += 1
      elsif record.to_date.present? && record.to_date < Date.today
        @report.n_passes += 1
      else
        @report.n_actifs += 1
      end
      @report.n_rattaches_fourretout += 1 unless Customer.exploitable_email?(record.email)
    end

    def upsert_customer_for(record)
      if Customer.exploitable_email?(record.email)
        email = Customer.normalize_email(record.email)
        upsert_customer(email: email, attrs: customer_attrs_from(record))
      else
        catch_all_customer
      end
    end

    def customer_attrs_from(record)
      {
        first_name: record.try(:firstname),
        last_name: record.try(:lastname),
        phone: record.try(:phone),
        organization_name: record.try(:group_name).presence,
        customer_type: record.try(:group_name).present? ? "organization" : "individual"
      }
    end

    def upsert_customer(email:, attrs:)
      return @customer_cache[email] if @customer_cache.key?(email)

      existing = Customer.unscoped.find_by(email: email)
      if existing
        @report.n_customers_upserted += 1
        @customer_cache[email] = existing
        return existing
      end

      customer = Customer.new(attrs.merge(email: email))
      customer.save!(validate: false) # legacy data may be incomplete; key is the email
      @report.n_customers_created += 1
      @customer_cache[email] = customer
    end

    def catch_all_customer
      return @catch_all if @catch_all
      email = Customer::CATCH_ALL_EMAIL
      existing = Customer.unscoped.find_by(email: email)
      if existing
        @report.n_customers_upserted += 1 unless @customer_cache.key?(email)
        @customer_cache[email] = existing
        return @catch_all = existing
      end
      customer = Customer.new(
        email: email,
        first_name: "Client",
        last_name: "Les 4 Sources",
        customer_type: "individual",
        language: "fr"
      )
      customer.save!(validate: false)
      customer.notes = "Customer fourre-tout migration — re-ventiler les stays vers de vrais clients via fusion de doublons."
      customer.save!(validate: false)
      @report.n_customers_created += 1
      @customer_cache[email] = customer
      @catch_all = customer
    end
  end
end
