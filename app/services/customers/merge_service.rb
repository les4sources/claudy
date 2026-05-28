module Customers
  # Fusion de doublons. Reassigns stays from a source Customer onto a target
  # Customer, then soft-deletes the source IF it has no remaining stays.
  #
  # This single rule serves both:
  #   - full duplicate merge (AC-15/16/17/18): move ALL stays -> source emptied
  #     -> source soft-deleted, target enriched.
  #   - catch-all re-ventilation (AC-50): move a SUBSET of stays from
  #     client@les4sources.be onto a real customer via the same code path; the
  #     catch-all keeps its remaining stays and stays active.
  #
  # Deterministic attribute rule (AC-18): the TARGET wins. The source value is
  # copied onto the target ONLY when the target's value is blank.
  class MergeService < ServiceBase
    MERGEABLE_BLANK_FILL = %i[
      human_id stripe_customer_id phone vat_number peppol_id
      address_line address_zip address_city address_country
    ].freeze

    attr_reader :source, :target, :stays_moved

    def initialize(source:, target:)
      @source = source
      @target = target
      @stays_moved = 0
    end

    # stay_ids: which stays to move. nil => all of the source's stays (full merge).
    def run(stay_ids: nil)
      return set_error_message("Source et cible doivent être deux clients distincts.") && false if source.nil? || target.nil? || source.id == target.id

      catch_error(context: { source: source.id, target: target.id }) do
        ActiveRecord::Base.transaction do
          stays_to_move = source.stays
          stays_to_move = stays_to_move.where(id: stay_ids) if stay_ids.present?

          stays_to_move.find_each do |stay|
            stay.update!(customer_id: target.id) # tracked by PaperTrail (AC-17)
            @stays_moved += 1
          end

          fill_blank_target_attributes!

          # Soft-delete the source only once it carries no more stays. A full
          # merge empties it (soft-deleted); a partial re-ventilation leaves it
          # active while other stays remain (AC-50).
          source.reload
          source.soft_delete!(validate: false) if source.stays.reload.empty?

          true
        end
      end
    end

    private

    def fill_blank_target_attributes!
      updates = {}
      MERGEABLE_BLANK_FILL.each do |attr|
        target_value = target.public_send(attr)
        source_value = source.public_send(attr)
        updates[attr] = source_value if target_value.blank? && source_value.present?
      end
      target.update!(updates) if updates.any?
    end
  end
end
