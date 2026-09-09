module Households
  # Rattache chaque membre de ménage à la personne qui porte le même nom
  # (epic Batch cooking #246).
  #
  # Le batch cooking paie le cuisinier sur son COMPTE PERSONNEL, et un compte
  # personnel se rattache à un `Human`. Un membre de ménage sans `human_id` ne
  # peut donc pas être payé — l'écran de saisie le dit et propose de créer la
  # personne, mais les huit adultes du lieu ont déjà la leur : c'est un
  # rattachement à faire, pas des fiches à créer.
  #
  # Trois règles, et elles sont là pour la même raison — un rattachement décide
  # à qui on doit de l'argent, donc le service ne devine jamais :
  #
  #   1. Correspondance sur le nom EXACT, insensible à la casse et aux espaces
  #      de bord. Rien d'approchant, rien de phonétique.
  #   2. Deux personnes du même nom = on ne touche à rien, et on le signale.
  #   3. Un membre déjà rattaché n'est jamais réécrit, même si son nom a changé
  #      depuis. Le lien existant fait foi.
  #
  # `ALIASES` porte les écarts de nom validés à la main. Un seul aujourd'hui :
  # le ménage dit « Stéphanie », l'annuaire dit « Steph » — même personne,
  # confirmé par Michael le 2026-09-09.
  class LinkMembersToHumans
    ALIASES = { "stéphanie" => "steph" }.freeze

    Result = Struct.new(:linked, :already_linked, :ambiguous, :unmatched, keyword_init: true) do
      def summary
        "#{linked.size} rattaché(s), #{already_linked} déjà en place, " \
        "#{ambiguous.size} ambigu(s), #{unmatched.size} sans personne connue"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(linked: [], already_linked: 0, ambiguous: [], unmatched: [])

      members.each do |member|
        if member.human_id.present?
          result.already_linked += 1
          next
        end

        candidates = humans_by_name[lookup_key(member.name)] || []
        case candidates.size
        when 0 then result.unmatched << label(member)
        when 1 then link(member, candidates.first, result)
        else result.ambiguous << "#{label(member)} → #{candidates.size} personnes du même nom"
        end
      end

      result
    end

    private

    # Les membres encore présents. Un départ n'a plus à être rattaché, et le
    # `default_scope` de soft-deletion écarte déjà les lignes supprimées.
    def members
      HouseholdMember.where(ended_on: nil).includes(:household).order(:id)
    end

    # `Human` porte un `default_scope where(status: "active")` : quelqu'un qui a
    # quitté le lieu n'est donc pas candidat, et c'est voulu — on ne rouvre pas
    # un compte personnel pour une personne partie.
    def humans_by_name
      @humans_by_name ||= Human.all.group_by { |human| normalize(human.name) }
    end

    def lookup_key(name)
      key = normalize(name)
      ALIASES.fetch(key, key)
    end

    def normalize(value) = value.to_s.strip.downcase

    def label(member) = "#{member.name} (#{member.household&.name})"

    def link(member, human, result)
      result.linked << "#{label(member)} → #{human.name}"
      return if @dry_run

      member.update!(human: human)
    end
  end
end
