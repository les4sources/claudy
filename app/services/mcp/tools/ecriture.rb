module Mcp
  module Tools
    # Un outil qui ÉCRIT. Il ne le fait jamais au premier appel.
    #
    # 1. Sans `confirmation`, il calcule ce qu'il ferait, le décrit, et rend un
    #    code de confirmation signé. Rien n'est écrit.
    # 2. Avec ce code, il recalcule le même plan. S'il a changé entre-temps
    #    (une ligne supprimée, un règlement encodé à côté), il refuse : on
    #    n'applique que ce que l'humain a vu.
    #
    # Le code vaut quinze minutes, pour cet outil, ce plan et cet utilisateur.
    # Tout ce qui s'écrit passe par PaperTrail, signé « claude:<e-mail> ».
    class Ecriture < Base
      VALIDITE = 15.minutes

      MOTIF = {
        type: "string",
        description: "Pourquoi cette correction (ex. « double facturation des poulets, retour de Seb »). " \
                     "Inscrit dans l'historique."
      }.freeze

      CONFIRMATION = {
        type: "string",
        description: "Code rendu par l'aperçu. À ne passer qu'après l'accord explicite de l'utilisateur sur cet aperçu."
      }.freeze

      # `resume` : les lignes de l'aperçu. `empreinte` : ce qui sera écrit,
      # réduit à des valeurs simples — c'est elle que signe la confirmation.
      Plan = Struct.new(:resume, :empreinte, :donnees, keyword_init: true)

      def self.read_only? = false

      # Un outil qui prévient quelqu'un (email au client, à la cuisine) laisse
      # le service métier tenir SA transaction : l'email ne part qu'une fois
      # l'écriture validée, jamais pour une écriture ensuite annulée.
      def self.transactionnel? = true

      def self.tool(name, title:, description:, schema:)
        schema = schema.deep_dup
        schema[:properties] = { motif: MOTIF }.merge(schema.fetch(:properties, {})).merge(confirmation: CONFIRMATION)
        super(name, title: title, description: "#{description}\n\n#{MODE_D_EMPLOI}", schema: schema)
      end

      MODE_D_EMPLOI = "Premier appel sans `confirmation` : aperçu seul, rien n'est écrit. " \
                      "Montre l'aperçu à l'utilisateur ; s'il dit oui, rappelle l'outil avec les mêmes " \
                      "arguments et le code `confirmation` rendu.".freeze

      def call(arguments)
        @motif = arguments["motif"].to_s.strip
        plan = planifier(arguments)
        code = arguments["confirmation"].to_s.strip
        return apercu(plan) if code.empty?

        verifier!(code, plan)
        resultat = PaperTrail.request(whodunnit: whodunnit) do
          self.class.transactionnel? ? ApplicationRecord.transaction { appliquer(plan) } : appliquer(plan)
        end
        "#{resultat}\n\nÉcrit dans Claudy. Historique signé « #{whodunnit} »."
      end

      private

      def planifier(_arguments) = raise(NotImplementedError)
      def appliquer(_plan) = raise(NotImplementedError)

      # L'auteur inscrit dans PaperTrail : le compte qui a autorisé Claude, et
      # le motif de la correction, pour qu'on sache plus tard POURQUOI.
      def whodunnit
        ["claude:#{user.email}", @motif.presence].compact.join(" — ").first(250)
      end

      # Ce que les comptes devront encore APRÈS l'écriture, calculé en jouant
      # l'écriture dans une transaction annulée. L'aperçu montre ainsi le
      # résultat, pas seulement le geste.
      def reste_du_apres(comptes)
        apres = {}
        PaperTrail.request(enabled: false) do
          # `requires_new` : un vrai point de sauvegarde. Sans lui, appelé dans
          # une transaction déjà ouverte, le Rollback serait avalé et l'aperçu
          # ÉCRIRAIT pour de bon.
          ApplicationRecord.transaction(requires_new: true) do
            yield
            comptes.each { |compte| apres[compte.id] = postes_dus(MemberAccount.find(compte.id)) }
            raise ActiveRecord::Rollback
          end
        end
        apres
      end

      # Joue `yield` pour de faux : dans un point de sauvegarde annulé, sans
      # historique. Sert aux aperçus qui doivent montrer le RÉSULTAT (total
      # recalculé, avertissements). À réserver aux services qui n'envoient pas
      # d'email : un email parti ne s'annule pas avec la transaction.
      def simuler
        resultat = nil
        PaperTrail.request(enabled: false) do
          ApplicationRecord.transaction(requires_new: true) do
            resultat = yield
            raise ActiveRecord::Rollback
          end
        end
        resultat
      end

      def postes_dus(compte)
        dus = MemberAccounts::Outstanding.new(compte)
        return "rien de dû" if dus.postes.empty?

        dus.postes.map { |poste| "#{poste.label} #{euros(poste.amount_cents)}" }.join(" · ")
      end

      def motif!(arguments)
        motif = arguments["motif"].to_s.strip
        raise Error, "Donne un motif : il sera inscrit dans l'historique." if motif.empty?

        motif
      end

      def apercu(plan)
        <<~TEXT.strip
          APERÇU — rien n'a été écrit.

          #{plan.resume}

          Pour appliquer, rappelle `#{self.class.tool_name}` avec les mêmes arguments et confirmation: "#{signer(plan)}"
          (valable #{VALIDITE.in_minutes.to_i} minutes, seulement après l'accord de l'utilisateur).
        TEXT
      end

      def signer(plan)
        verifier.generate({ "outil" => self.class.tool_name, "plan" => empreinte(plan), "user" => user.id },
                          expires_in: VALIDITE, purpose: :mcp_confirmation)
      end

      def verifier!(code, plan)
        signe = verifier.verified(code, purpose: :mcp_confirmation)
        if signe.nil? || signe["outil"] != self.class.tool_name || signe["user"] != user.id
          raise Error, "Code de confirmation invalide ou expiré. Refais l'aperçu (appel sans confirmation)."
        end
        return if signe["plan"] == empreinte(plan)

        raise Error, "Les arguments ou les données ont changé depuis l'aperçu : rien n'a été écrit. " \
                     "Voici le nouvel aperçu.\n\n#{apercu(plan)}"
      end

      def empreinte(plan)
        Digest::SHA256.hexdigest([plan.empreinte, @motif].to_json)
      end

      def verifier
        Rails.application.message_verifier("mcp")
      end
    end
  end
end
