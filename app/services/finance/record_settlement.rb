module Finance
  # Enregistre un règlement reçu (issue #160).
  #
  # UN encaissement = UN `AccountSettlement`. C'est la règle anti-double-compte
  # du lot, appliquée au compte courant : jamais deux règlements pour un même
  # virement. Le `AccountSettlement` porte les métadonnées de paiement (canal de
  # réception, communication brute), les écritures portent les montants.
  #
  # UNE ÉCRITURE PAR POSTE RÉGLÉ (2026-09-20). Un virement de 280 € qui paie
  # 230 € de charges et 50 € de dôme reste un seul paiement, ventilé en deux
  # écritures — c'est le poste porté par l'écriture qui permet à
  # `MemberAccounts::Outstanding` d'imputer poste par poste. Sans ventilation,
  # une seule écriture, comme avant.
  class RecordSettlement < ServiceBase
    # Levée quand la ventilation ne retombe pas sur le montant encaissé : mieux
    # vaut refuser que d'écrire un règlement qui ne vaut pas ce qu'il a coûté.
    class VentilationMismatch < StandardError; end

    # `flow` est le POSTE que ce règlement éteint — charges, bar, repas… C'est
    # lui qui permet à `MemberAccounts::Outstanding` d'imputer poste par poste :
    # sans lui, un virement de charges part éponger des consommations de bar et
    # le foyer voit ses charges réclamées alors qu'il vient de les payer
    # (Michael, 2026-09-20). Il reste facultatif, et vaut alors « Divers » : un
    # règlement dont on ne sait pas ce qu'il paie ne doit pas être rangé au
    # hasard dans un poste, il doit se voir.
    # `ventilation` répartit UN encaissement sur PLUSIEURS postes :
    # `{ "charges" => 23_000, "dome" => 5_000 }` pour le virement mensuel de Seb,
    # qui payait les deux. Sans elle, tout part sur `flow`. Une écriture par
    # poste, un seul `AccountSettlement` : le paiement reste unique, c'est sa
    # ventilation qui se démultiplie.
    def initialize(member_account:, amount_cents:, received_on:, method: "bank_transfer",
                   received_channel: "bank", reference: nil, notes: nil, whodunnit: nil,
                   flow: nil, ventilation: nil, idempotency_key: nil)
      @account = member_account
      @amount_cents = amount_cents.to_i
      @received_on = received_on
      @method = method
      @received_channel = received_channel
      @reference = reference
      @notes = notes
      @whodunnit = whodunnit
      @flow = flow.presence || "other"
      @ventilation = ventilation.presence&.transform_values(&:to_i)&.reject { |_, cents| cents.zero? }
      # Facultative : la saisie manuelle n'en a pas besoin — c'est un humain qui
      # tape, il voit ce qu'il a déjà tapé. Elle sert au rapprochement bancaire,
      # où rejouer la même ligne doit être sans effet.
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
      verifie_ventilation

      PaperTrail.request(whodunnit: @whodunnit || "settlement") do
        ApplicationRecord.transaction do
          settlement = AccountSettlement.create!(
            member_account: @account,
            amount_cents: @amount_cents.abs,
            received_on: @received_on,
            method: @method,
            received_channel: @received_channel,
            reference: @reference,
            notes: @notes
          )

          entries = repartition.map do |poste, cents|
            @account.account_entries.create!(
              entry_date: @received_on,
              posted_at: Time.current,
              amount_cents: -cents.abs,
              kind: "settlement",
              flow: poste,
              source: "settlement",
              label: label_for(poste),
              account_settlement: settlement,
              # La clé ne vaut que pour une ventilation simple : sur plusieurs
              # postes, chaque écriture doit avoir la sienne, sinon la seconde
              # se fait refuser par l'index et emporte la transaction.
              idempotency_key: cle_pour(poste)
            )
          end

          # `account_entry` reste renseigné : tout ce qui lisait le règlement
          # avant la ventilation continue de trouver son écriture.
          settlement.update!(account_entry: entries.first)
          settlement
        end
      end
    end

    # Un poste et son montant, ou la ventilation telle qu'elle a été demandée.
    def repartition
      @ventilation || { @flow => @amount_cents.abs }
    end

    def verifie_ventilation
      return if @ventilation.nil?

      total = @ventilation.values.sum(&:abs)
      return if total == @amount_cents.abs

      raise VentilationMismatch,
            "La ventilation totalise #{Money.new(total, 'EUR').format} " \
            "pour un encaissement de #{Money.new(@amount_cents.abs, 'EUR').format}."
    end

    # Une seule écriture : la clé passée par l'appelant, telle quelle. Plusieurs :
    # elle est suffixée du poste, sinon l'index d'unicité refuse la deuxième.
    def cle_pour(poste)
      return nil if @idempotency_key.blank?
      return @idempotency_key if repartition.size == 1

      "#{@idempotency_key}:#{poste}"
    end

    # Le canal de réception apparaît dans le libellé quand il diffère de la
    # banque : c'est ce qui rend lisible « payé au bar, encaissé à l'épicerie »
    # six mois plus tard.
    def label_for(poste = nil)
      base = "Règlement — #{AccountSettlement::METHOD_LABELS.fetch(@method, @method)}"
      base += " (#{AccountSettlement::CHANNEL_LABELS.fetch(@received_channel, @received_channel)})" unless @received_channel == "bank"
      # Le poste n'apparaît dans le libellé QUE s'il y en a plusieurs : sur un
      # règlement simple, la colonne Canal le dit déjà, et le répéter alourdit
      # une table qu'on lit en diagonale.
      return base if repartition.size == 1

      "#{base} — #{AccountEntry::FLOW_LABELS.fetch(poste, poste)}"
    end
  end
end
