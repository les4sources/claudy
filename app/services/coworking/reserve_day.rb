module Coworking
  # Réservation d'une journée de coworking par le client depuis le portail
  # (epic #126, Phase 3).
  #
  # Consomme 1 crédit d'un pack VIVANT et PAYÉ du client — le plus proche de son
  # expiration d'abord (FIFO expiration), pour ne pas laisser périmer un crédit
  # qu'on aurait pu utiliser. Un pack en attente de paiement ne réserve pas.
  #
  # Concurrence : la capacité (3 bureaux/jour, tous clients confondus) et le
  # dernier crédit d'un pack sont protégés par un verrou pessimiste FOR UPDATE
  # (même pattern que Stays::MergeService). Deux requêtes concurrentes sur le
  # même jour se sérialisent : la seconde re-compte SOUS le verrou et se voit
  # refuser la 4e réservation.
  class ReserveDay < ServiceBase
    attr_reader :reservation

    def initialize(customer:, date:)
      @customer = customer
      @date = date
      @report_errors = true
    end

    def run
      return false unless valid_date?

      catch_error(context: { customer: @customer.id, date: @date }) do
        ActiveRecord::Base.transaction do
          # Sérialise les réservations concurrentes du même jour : on verrouille
          # les lignes vivantes existantes, puis on re-compte sous le verrou.
          CoworkingReservation.unscoped
                              .where(date: @date, deleted_at: nil)
                              .lock("FOR UPDATE").to_a

          if CoworkingReservation.count_on(@date) >= CoworkingReservation::DAILY_CAPACITY
            set_error_message("Ce jour est complet — les trois bureaux sont déjà réservés.")
            raise ActiveRecord::Rollback
          end

          pack = pick_pack
          if pack.nil?
            set_error_message(no_pack_message)
            raise ActiveRecord::Rollback
          end

          @reservation = pack.coworking_reservations.create!(date: @date, customer: @customer)
        end
      end

      @reservation.present? && @reservation.persisted?
    end

    private

    def valid_date?
      if @date.blank?
        set_error_message("Date de réservation manquante.")
        return false
      end
      unless (1..5).cover?(@date.wday)
        set_error_message("Le coworking se réserve du lundi au vendredi.")
        return false
      end
      if @date < Date.current
        set_error_message("Cette journée est déjà passée.")
        return false
      end
      true
    end

    # Le pack qui financera la journée : vivant, payé, non expiré à la date, avec
    # au moins un crédit — expiration la plus proche d'abord. Verrouillé
    # (FOR UPDATE) et re-vérifié pour empêcher le double-usage du dernier crédit.
    def pick_pack
      candidate = live_paid_packs.find(&:credits_left?)
      return nil if candidate.nil?

      candidate.lock! # SELECT ... FOR UPDATE (recharge la ligne)
      return nil unless candidate.paid? && !candidate.expired?(@date) && candidate.credits_left?

      candidate
    end

    def live_paid_packs
      @customer.coworking_packs
               .order(expires_at: :asc)
               .to_a
               .select { |pack| !pack.expired?(@date) && pack.paid? }
    end

    # Message clair selon la raison du refus : aucun pack, pack en attente de
    # paiement, ou plus de crédit.
    def no_pack_message
      packs = @customer.coworking_packs.to_a
      live = packs.reject { |p| p.expired?(@date) }

      return "Vous n'avez pas encore de pack de coworking. Achetez-en un pour réserver." if live.empty?
      if live.any? { |p| p.payment_status == "pending" } && live.none? { |p| p.paid? && p.credits_left? }
        return "Votre pack est en attente de paiement. Il sera utilisable dès que le paiement sera confirmé."
      end

      "Vous n'avez plus de journée disponible. Achetez un nouveau pack pour continuer à réserver."
    end
  end
end
