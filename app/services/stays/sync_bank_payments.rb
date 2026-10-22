module Stays
  # Une ligne de banque ventilée sur un séjour PAIE ce séjour (Michael,
  # 2026-10-22 : « quand j'affecte un paiement à un séjour, ce serait logique
  # qu'un paiement soit créé sur le séjour »). Avant, l'affectation passait les
  # recettes au grand livre mais le séjour restait « en attente » : il revenait
  # dans la file et gonflait « à encaisser ».
  #
  # Comme le paiement d'une facture d'achat, c'est un RAPPROCHEMENT qu'on
  # constate, pas une case qu'on coche : les affectations qui pointent le
  # séjour font foi, dans les deux sens. Pour chaque ligne qui le pointe :
  #
  #   1. un paiement déjà relié à la ligne suit son montant ;
  #   2. sinon, un paiement que l'Accueil avait DÉJÀ encodé à la main, du même
  #      montant et pas encore relié, est relié — jamais de doublon ;
  #   3. s'il reste des paiements encodés à la main sans ligne en face, mais
  #      d'un autre montant (deux acomptes pour un virement, un montant arrondi),
  #      on ne crée RIEN : « souvent ils ont été créés à la main » (Michael).
  #      Un humain tranche, l'écran et le rattrapage le signalent ;
  #   4. si le séjour est déjà soldé, on ne crée rien non plus ;
  #   5. sinon seulement, un paiement est créé (« Virement », « Liquide » pour
  #      la caisse), encaissé à la date de la ligne.
  #
  # Une affectation retirée défait ce qu'elle a fait : le paiement créé
  # disparaît (suppression douce), le paiement relié est simplement détaché.
  #
  # Les lignes des comptes Stripe sont ignorées : le paiement Stripe du séjour
  # existe déjà, posé par le paiement en ligne, et `VentilateStripePayout` met
  # le séjour en document de ses recettes. Pour la même raison, un paiement
  # « En ligne » ou porteur d'un paiement Stripe n'est jamais relié.
  class SyncBankPayments < ServiceBase
    # Les moyens d'un paiement encodé à la main qui peut être l'argent d'une
    # ligne de banque ou de caisse. Ni « En ligne » (Stripe), ni le miroir
    # Tranches de Vie.
    MANUAL_METHODS = (%w[bank_transfer cash] + [Payment::OTA_METHOD] + Payment::LEGACY_OTA_METHODS).freeze

    # Ce que chaque ligne a fait du séjour, par id de ligne :
    #   :created, :linked, :kept (déjà relié), :unmatched (paiement à la main
    #   d'un autre montant, rien créé), :settled (séjour déjà soldé).
    attr_reader :outcomes

    def initialize(stay:)
      @stay = stay
      @outcomes = {}
    end

    def run = catch_error(context: { stay: @stay&.id }) { sync }
    def run! = sync

    # La phrase qui dit, après une ventilation, ce que la ligne a fait du
    # séjour. Se lit sur l'état : la synchronisation a déjà tourné au commit.
    def self.summary(stay:, cash_entry:)
      return if cash_entry.amount_cents <= 0 || cash_entry.cash_account&.stripe?

      paiement = stay.payments.find_by(cash_entry_id: cash_entry.id)
      montant = ->(cents) { Money.new(cents, "EUR").format }

      if paiement&.created_from_cash_entry?
        "Paiement de #{montant.call(paiement.amount_cents)} ajouté au séjour ##{stay.id}."
      elsif paiement
        "Le paiement de #{montant.call(paiement.amount_cents)} déjà encodé sur le séjour ##{stay.id} est relié à cette ligne."
      elsif new(stay: stay).paiements_a_la_main.any?
        "Aucun paiement ajouté au séjour ##{stay.id} : il porte un paiement encodé à la main d'un autre montant. " \
          "Vérifie sur la fiche du séjour."
      else
        "Le séjour ##{stay.id} était déjà soldé : aucun paiement ajouté. Vérifie qu'il n'y a pas un doublon."
      end
    end

    # Les paiements encodés à la main qu'aucune ligne n'explique encore.
    def paiements_a_la_main
      @stay.payments.where(cash_entry_id: nil, stripe_payment_intent_id: nil,
                           payment_method: MANUAL_METHODS, status: %w[paid pending])
    end

    private

    def sync
      return if @stay.blank?

      ApplicationRecord.transaction do
        montants = montants_par_ligne

        # D'abord ce qui n'a plus de ligne en face : sinon un paiement relié à
        # une affectation retirée compterait encore dans le solde qu'on lit
        # juste après pour décider d'en créer un.
        @stay.payments.where.not(cash_entry_id: nil).find_each do |paiement|
          liberer(paiement) unless montants.key?(paiement.cash_entry_id)
        end
        # Un paiement créé par une ligne depuis supprimée (la clé étrangère a mis
        # `cash_entry_id` à nul) n'a plus rien qui le justifie.
        @stay.payments.where(cash_entry_id: nil, created_from_cash_entry: true).find_each do |paiement|
          paiement.soft_delete!(validate: false)
        end

        lignes = CashEntry.where(id: montants.keys).includes(:cash_account).order(:entry_date, :id)
        lignes.each { |ligne| @outcomes[ligne.id] = rapprocher(ligne, montants.fetch(ligne.id)) }
      end

      @stay.set_payment_status
      @stay
    end

    # Le montant affecté au séjour, ligne par ligne. Seulement les lignes
    # entrantes hors Stripe : un remboursement (ligne sortante) ne se lit pas
    # comme un paiement, et Stripe a déjà le sien.
    def montants_par_ligne
      CashAllocation.outside_stripe
                    .where(document: @stay)
                    .group(:cash_entry_id)
                    .sum(:amount_cents)
                    .select { |_ligne, montant| montant.positive? }
    end

    def rapprocher(ligne, montant)
      paiement = @stay.payments.find_by(cash_entry_id: ligne.id)
      if paiement
        ajuster(paiement, ligne, montant) if paiement.created_from_cash_entry?
        return :kept
      end

      if (deja_encode = paiement_a_relier(ligne, montant))
        attributs = { cash_entry_id: ligne.id }
        # Un virement annoncé « en attente » est arrivé : la banque le prouve.
        attributs.merge!(status: "paid", paid_on: deja_encode.paid_on || ligne.entry_date) if deja_encode.pending?
        deja_encode.update!(attributs)
        return :linked
      end

      return :unmatched if paiements_a_la_main.any?
      return :settled if solde?

      Payment.create!(stay: @stay, cash_entry: ligne, created_from_cash_entry: true,
                      amount_cents: montant, payment_method: moyen(ligne), status: "paid",
                      paid_on: ligne.entry_date)
      :created
    end

    # Le paiement encodé à la main pour CET argent : même montant. Le même
    # moyen d'abord, puis le plus proche de la date de la ligne.
    def paiement_a_relier(ligne, montant)
      paiements_a_la_main.where(amount_cents: montant).min_by do |paiement|
        [paiement.payment_method == moyen(ligne) ? 0 : 1, (paiement.effective_date - ligne.entry_date).abs]
      end
    end

    def ajuster(paiement, ligne, montant)
      return if paiement.amount_cents == montant && paiement.paid_on == ligne.entry_date

      paiement.update!(amount_cents: montant, paid_on: ligne.entry_date)
    end

    def liberer(paiement)
      # Le paiement créé garde sa ligne d'origine : PaperTrail et la colonne
      # disent encore d'où il venait, une fois supprimé.
      if paiement.created_from_cash_entry?
        paiement.soft_delete!(validate: false)
      else
        paiement.update!(cash_entry_id: nil)
      end
    end

    # Encaissé, et plus rien d'exigible : le séjour n'attend plus d'argent.
    def solde?
      @stay.amount_paid_cents.positive? && @stay.balance_due_cents <= 0
    end

    def moyen(ligne) = ligne.cash_account&.kind == "cash" ? "cash" : "bank_transfer"
  end
end
