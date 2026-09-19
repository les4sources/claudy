module Finance
  # Enregistre un règlement reçu (issue #160).
  #
  # UN règlement = UNE écriture négative + UN `AccountSettlement` qui la
  # documente. Jamais deux écritures : c'est la règle anti-double-compte du lot,
  # appliquée ici à l'échelle du compte courant. Le `AccountSettlement` porte les
  # métadonnées de paiement (canal de réception, communication brute), l'écriture
  # porte le montant.
  class RecordSettlement < ServiceBase
    # `idempotency_key` est facultative : la saisie manuelle n'en a pas besoin —
    # c'est un humain qui tape, il voit ce qu'il a déjà tapé. Elle sert au
    # rapprochement bancaire (issue #349), où rejouer la même ligne doit être
    # sans effet plutôt que de créer un second règlement.
    def initialize(member_account:, amount_cents:, received_on:, method: "bank_transfer",
                   received_channel: "bank", reference: nil, notes: nil, whodunnit: nil,
                   idempotency_key: nil)
      @account = member_account
      @amount_cents = amount_cents.to_i
      @received_on = received_on
      @method = method
      @received_channel = received_channel
      @reference = reference
      @notes = notes
      @whodunnit = whodunnit
      @idempotency_key = idempotency_key
    end

    def run
      catch_error(context: { account: @account.id }) { record }
    end

    def run!
      record
    end

    private

    def record
      PaperTrail.request(whodunnit: @whodunnit || "settlement") do
        ApplicationRecord.transaction do
          entry = @account.account_entries.create!(
            entry_date: @received_on,
            posted_at: Time.current,
            amount_cents: -@amount_cents.abs,
            kind: "settlement",
            flow: "other",
            source: "settlement",
            label: label_for,
            idempotency_key: @idempotency_key
          )

          AccountSettlement.create!(
            member_account: @account,
            account_entry: entry,
            amount_cents: @amount_cents.abs,
            received_on: @received_on,
            method: @method,
            received_channel: @received_channel,
            reference: @reference,
            notes: @notes
          )
        end
      end
    end

    # Le canal de réception apparaît dans le libellé quand il diffère de la
    # banque : c'est ce qui rend lisible « payé au bar, encaissé à l'épicerie »
    # six mois plus tard.
    def label_for
      base = "Règlement — #{AccountSettlement::METHOD_LABELS.fetch(@method, @method)}"
      return base if @received_channel == "bank"

      "#{base} (#{AccountSettlement::CHANNEL_LABELS.fetch(@received_channel, @received_channel)})"
    end
  end
end
