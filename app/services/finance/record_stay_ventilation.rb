module Finance
  # Le geste « Ventiler ce séjour » sur une ligne entrante : le montant choisi
  # est réparti selon le devis du séjour (`VentilateStay`), chaque part pointe
  # le séjour, l'IBAN du tiers est appris pour son client, et la ligne est
  # comptabilisée si elle est entièrement affectée.
  #
  # Le montant n'est plus forcément toute la ligne (Michael, 2026-10-30 :
  # 74 € reçus pour un séjour au prix imposé de 70 €, et 4 € de bar). Sans
  # montant, on ventile ce que la ligne peut encore porter ; avec un montant,
  # le reste attend une affectation à la main, comme toute ligne entamée.
  # Partagé par la fiche, la file « À affecter » et l'outil MCP.
  class RecordStayVentilation < ServiceBase
    class InvalidAmount < StandardError; end

    def initialize(stay:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @stay = stay
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { stay: @stay&.id, cash_entry: @entry&.id }) { record }
    def run! = record

    private

    def record
      ApplicationRecord.transaction do
        @entry.lock!

        # Le montant se lit APRÈS le verrou : lu avant, il pourrait dépasser ce
        # que la ligne porte encore.
        montant = montant!
        lignes = VentilateStay.new(stay: @stay, amount_cents: montant).run!
        entite = @entry.cash_account.legal_entity

        lignes.each do |ligne|
          @entry.cash_allocations.create!(
            general_account: ligne.general_account,
            team: ligne.team,
            legal_entity: entite,
            amount_cents: ligne.amount_cents,
            document: @stay,
            label: ligne.label
          )
        end

        CustomerBankAccount.remember!(customer: @stay.customer, iban: @entry.counterparty_iban,
                                      holder_name: @entry.counterparty_name)

        if @entry.reload.fully_allocated?
          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
        end

        lignes
      end
    end

    def montant!
      reste = @entry.reload.remaining_cents
      raise InvalidAmount, "Cette ligne est déjà entièrement affectée." if reste.zero?
      return reste if @amount_cents.nil?

      if @amount_cents <= 0
        raise InvalidAmount, "Le montant à ventiler doit être positif."
      elsif @amount_cents > reste.abs
        raise InvalidAmount,
              "La ligne ne porte plus que #{Money.new(reste.abs, 'EUR').format} : " \
              "impossible d'en ventiler #{Money.new(@amount_cents, 'EUR').format} sur le séjour."
      end

      reste.negative? ? -@amount_cents : @amount_cents
    end
  end
end
