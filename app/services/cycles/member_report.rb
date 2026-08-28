module Cycles
  # Bilan d'un membre sur un cycle : heures planifiées / faites / reportées /
  # abandonnées, et les listes correspondantes. Une action « reportée »
  # (catégorie) n'est jamais comptée dans le planifié : c'est un sas, pas un
  # engagement.
  class MemberReport
    attr_reader :human, :cycle, :actions

    def self.for_cycle(cycle, humans: nil)
      humans ||= Human.cycle_active.roles_enabled.order(:name)
      actions_by_human = cycle.cycle_actions.includes(:delegate_to_human, :deferred_from).group_by(&:human_id)
      humans.map { |h| new(human: h, cycle: cycle, actions: actions_by_human[h.id] || []) }
    end

    def initialize(human:, cycle:, actions: nil)
      @human = human
      @cycle = cycle
      @actions = actions || cycle.cycle_actions.where(human: human).to_a
    end

    def engaged_actions = actions.reject(&:reportee?)
    def planned_hours = hours_of(engaged_actions)

    # Faites : issue « done », ou — cycle encore ouvert — simplement cochées.
    def done_actions = actions.select { |a| a.outcome_done? || (a.outcome.nil? && a.completed?) }
    def done_hours = hours_of(done_actions.reject(&:reportee?))

    def deferred_actions = actions.select(&:outcome_deferred?)
    def deferred_hours = hours_of(deferred_actions.reject(&:reportee?))

    def dropped_actions = actions.select(&:outcome_dropped?)
    def dropped_hours = hours_of(dropped_actions.reject(&:reportee?))

    # Encore en jeu et non cochée : ce que la clôture doit trancher.
    def pending_actions = actions.select { |a| a.live? && !a.completed? }
    def pending_hours = hours_of(pending_actions.reject(&:reportee?))

    def live_actions = actions.select(&:live?)

    def completion_ratio
      return 0.0 if planned_hours <= 0
      (done_hours / planned_hours).clamp(0, 1)
    end

    def empty? = actions.empty?

    private

    def hours_of(list)
      list.sum { |a| a.hours.to_f }
    end
  end
end
