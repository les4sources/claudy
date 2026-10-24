# frozen_string_literal: true

module Projects
  # La page Projets de la nouvelle interface (Michael 2026-10-24, « s'inspirer
  # de Basecamp ») : chaque projet est une carte qu'on reconnaît d'un coup
  # d'œil (nom, de quoi il s'agit, qui s'y active, où il en est), rangée sous
  # son pôle ; à côté, les actions confiées à la personne qui regarde.
  #
  # Deux vues : les projets qui vivent (en cours, puis en pause) et les
  # projets terminés. Les comptes d'actions viennent de `Projects::TaskStats`,
  # les mêmes que sur la page du pôle.
  class Home
    VIEWS = %w[ongoing done].freeze
    MY_TASKS_LIMIT = 8

    Card = Struct.new(:project, :done_count, :total_count, :overdue_count, :people, :today, keyword_init: true) do
      def percent = total_count.zero? ? 0 : (done_count * 100.0 / total_count).round
      def late? = project.due_date.present? && project.due_date < today && !project.done?
      def paused? = project.status == "paused"
    end

    attr_reader :view, :today, :human

    def initialize(human:, view: nil, today: Date.current)
      @human = human
      @view = VIEWS.include?(view) ? view : "ongoing"
      @today = today
    end

    def done_view? = view == "done"

    # [[pôle ou nil, [Card, …]], …] : les pôles par nom, les projets sans pôle
    # en dernier pour qu'on les rattache.
    def groups
      cards.select { |card| card.project.done? == done_view? }
           .group_by { |card| card.project.team }
           .sort_by { |team, _| team ? [0, team.name.to_s.downcase] : [1, ""] }
           .map { |team, list| [team, sort(list)] }
    end

    def counts = @counts ||= cards.map { |card| card.project.status }.tally
    def ongoing_count = counts["active"].to_i + counts["paused"].to_i
    def done_count = counts["done"].to_i
    def overdue_tasks_count = cards.reject { |card| card.project.done? }.sum(&:overdue_count)

    # La phrase du haut, en trois morceaux : avant, mot surligné, après.
    def phrase
      active = counts["active"].to_i
      paused = counts["paused"].to_i
      return ["Aucun projet ne tourne en ce moment. ", "Lance le premier", "."] if active.zero? && paused.zero?

      overdue = overdue_tasks_count
      late = overdue.positive? ? " et #{plural(overdue, 'action a passé son échéance', 'actions ont passé leur échéance')}" : ""
      if active.zero?
        return ["Rien n’avance en ce moment : ", plural(paused, "projet en pause", "projets en pause"), "#{late}."]
      end

      pause = paused.positive? ? ", #{plural(paused, 'est en pause', 'sont en pause')}" : ""
      ["", plural(active, "projet avance", "projets avancent"), "#{pause}#{late}."]
    end

    # Les actions encore ouvertes confiées à la personne, la plus urgente d'abord.
    def my_tasks
      return [] if human.nil?

      @my_tasks ||= TaskStats.open_tasks(Project.select(:id))
                             .joins(:humans).where(humans: { id: human.id })
                             .includes(:project)
                             .order(Arel.sql("tasks.due_date IS NULL, tasks.due_date, tasks.id"))
                             .limit(MY_TASKS_LIMIT).to_a
    end

    private

    def cards
      @cards ||= begin
        projects = Project.includes(:human, :team, :rich_text_description).to_a
        ids = projects.map(&:id)
        stats = TaskStats.counts(ids, today: today)
        assignees = TaskStats.assignees(ids)
        projects.map do |project|
          done, total, overdue = stats.fetch(project.id, [0, 0, 0])
          people = ([project.human] + assignees.fetch(project.id, [])).compact.uniq
          Card.new(project: project, done_count: done, total_count: total, overdue_count: overdue,
                   people: people, today: today)
        end
      end
    end

    # En cours avant en pause ; puis l'échéance la plus proche, les projets sans
    # échéance à la fin. Les terminés : le plus récemment touché d'abord.
    def sort(list)
      return list.sort_by { |card| -card.project.updated_at.to_i } if done_view?

      list.sort_by do |card|
        [card.paused? ? 1 : 0, card.project.due_date || Date.new(9999), card.project.name.to_s.downcase]
      end
    end

    def plural(count, one, many) = "#{count} #{count > 1 ? many : one}"
  end
end
