module Rates
  # Édition datée d'un tarif (issue #156).
  #
  # Trois effets, dans une seule transaction :
  #   1. une version est ouverte à `active_from` (ou éditée si elle existe déjà,
  #      pour qu'une deuxième correction le même jour ne laisse pas deux lignes) ;
  #   2. la version qui couvrait cette date est close la veille ;
  #   3. le miroir `rates.amount_cents` n'est mis à jour QUE si la nouvelle
  #      version couvre aujourd'hui — c'est ce qui permet de programmer un prix
  #      pour le mois prochain sans toucher au devis d'aujourd'hui.
  #
  # Rien n'est jamais réécrit sur les versions passées : un décompte déjà émis
  # continue de lire les montants de son époque.
  class UpdateAmount < ServiceBase
    attr_reader :rate, :version

    def initialize(rate:)
      @rate = rate
      @report_errors = true
    end

    def run(amount_cents:, active_from: nil, note: nil)
      context = { rate_id: rate.id, amount_cents: amount_cents, active_from: active_from }

      catch_error(context: context) do
        run!(amount_cents: amount_cents, active_from: active_from, note: note)
      end
    end

    def run!(amount_cents:, active_from: nil, note: nil)
      from = normalize_date(active_from) || Date.current

      ActiveRecord::Base.transaction do
        @version = upsert_version(amount_cents: amount_cents, from: from, note: note)
        rate.update!(amount_cents: amount_cents) if @version.covers?(Date.current)
      end

      Pricing::Rates.reset!
      true
    end

    private

    def upsert_version(amount_cents:, from:, note:)
      existing = rate.rate_versions.find_by(active_from: from)

      if existing
        existing.update!(amount_cents: amount_cents, note: note.presence || existing.note)
        return existing
      end

      rate.rate_versions.covering(from).each { |previous| previous.update!(active_until: from - 1) }

      rate.rate_versions.create!(
        amount_cents: amount_cents,
        active_from: from,
        active_until: following_start(from)&.prev_day,
        note: note.presence
      )
    end

    # Une édition antérieure à une version déjà ouverte s'insère entre les deux :
    # elle s'arrête la veille de celle qui suit.
    def following_start(from)
      rate.rate_versions.where(active_from: from..).chronological.first&.active_from
    end

    def normalize_date(value)
      return nil if value.blank?
      return value.to_date if value.respond_to?(:to_date)

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
