module Finance
  # Les membres à qui la maison doit de l'argent (epic #246, phase 2).
  #
  # Un compte personnel dont le solde est NÉGATIF est un solde en faveur de la
  # personne : c'est un payable. La file « À payer » de l'epic #240 (phase 4)
  # n'existe pas encore ; en attendant, cette liste vit sur l'écran Batch
  # cooking — un cuisinier qu'on oublie de payer est le meilleur moyen de ne
  # plus en avoir.
  #
  # Un compte sans IBAN est RENVOYÉ QUAND MÊME, marqué : le masquer reviendrait
  # à faire disparaître la dette parce qu'il manque une coordonnée.
  class MemberPayables
    Row = Struct.new(:member_account, :human, :due_cents, :iban, :iban_holder, keyword_init: true) do
      def payable? = iban.present?
      def communication = member_account.code
    end

    def initialize(kind: "human")
      @kind = kind
    end

    def rows
      @rows ||= begin
        comptes = MemberAccount.where(kind: @kind).includes(:human, :account_entries).ordered

        comptes.filter_map do |compte|
          du = -compte.balance_cents
          next unless du.positive?

          Row.new(member_account: compte, human: compte.human, due_cents: du,
                  iban: iban_de(compte.human), iban_holder: compte.human&.iban_holder)
        end
      end
    end

    # Un IBAN qu'on n'arrive pas à déchiffrer vaut « pas d'IBAN ».
    #
    # Les IBAN sont chiffrés au repos avec les clés de l'environnement. Une
    # copie locale de la base de production porte donc des IBAN illisibles —
    # les clés de développement sont fixes et publiques, exprès. Sans ce
    # filet, `bin/sync-production-database` rendait la file « À affecter »
    # entièrement inaccessible en local, sur une erreur de déchiffrement qui ne
    # disait pas son nom.
    #
    # Le rattrapage ne masque rien d'important : ici l'IBAN sert à PROPOSER un
    # rapprochement, et une ligne sans IBAN se propose quand même sur le
    # montant. Le compte apparaît alors comme « sans IBAN », ce que cet écran
    # sait déjà montrer.
    def iban_de(human)
      human&.iban
    rescue ActiveRecord::Encryption::Errors::Decryption
      nil
    end

    def total_cents = rows.sum(&:due_cents)
    def any? = rows.any?
    def without_iban = rows.reject(&:payable?)
  end
end
