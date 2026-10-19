module Teams
  # Les projets d'un pôle (Michael, 2026-10-19), tels que la page du pôle les
  # montre : ceux qui avancent ou attendent, avec l'avancement de leurs
  # actions, puis les prochaines actions à faire, et enfin les projets finis.
  #
  # Comme pour ses comptes, un pôle qui en regroupe d'autres voit aussi leurs
  # projets : la hiérarchie s'arrête à deux niveaux.
  #
  # Une action est faite quand elle est « Terminée » ; une action « Annulée »
  # ne compte ni dans le fait ni dans le total. Une action sans statut (celles
  # qu'on ajoute depuis la page du projet) est à faire.
  class ProjectBoard
    UPCOMING_LIMIT = 8

    Row = Struct.new(:project, :done_count, :total_count, :overdue_count, :today, keyword_init: true) do
      def percent = total_count.zero? ? 0 : (done_count * 100.0 / total_count).round
      def late? = project.due_date.present? && project.due_date < today && !project.done?
    end

    attr_reader :team, :today

    def initialize(team:, today: Date.current)
      @team = team
      @today = today
    end

    def teams = @teams ||= [team] + team.children.to_a
    def sub_teams? = teams.size > 1

    # En cours d'abord, puis en pause ; dans chaque groupe, l'échéance la plus
    # proche en tête et les projets sans échéance à la fin.
    def ongoing
      rows.reject { |row| row.project.done? }.sort_by do |row|
        [row.project.status == "active" ? 0 : 1, row.project.due_date || Date.new(9999), row.project.name.to_s.downcase]
      end
    end

    def finished
      rows.select { |row| row.project.done? }.sort_by { |row| -row.project.updated_at.to_i }
    end

    def counts = rows.map { |row| row.project.status }.tally

    # Les actions encore à faire des projets en cours, la plus urgente d'abord.
    def upcoming_tasks
      ids = rows.select { |row| row.project.status == "active" }.map { |row| row.project.id }
      return [] if ids.empty?

      open_tasks(ids)
        .includes(:humans, :project)
        .order(Arel.sql("tasks.due_date IS NULL, tasks.due_date, tasks.id"))
        .limit(UPCOMING_LIMIT)
        .to_a
    end

    private

    def rows
      @rows ||= begin
        projects = Project.where(team_id: teams.map(&:id)).includes(:human, :team).to_a
        stats = task_stats(projects.map(&:id))
        projects.map do |project|
          done, total, overdue = stats.fetch(project.id, [0, 0, 0])
          Row.new(project: project, done_count: done, total_count: total, overdue_count: overdue, today: today)
        end
      end
    end

    # Une requête pour tous les projets : [faites, total, en retard] par projet.
    def task_stats(project_ids)
      return {} if project_ids.empty?

      live_tasks(project_ids)
        .group(:project_id)
        .pluck(
          :project_id,
          Arel.sql("COUNT(*) FILTER (WHERE tasks.status = '#{Task::STATUS_CLOSED}')"),
          Arel.sql("COUNT(*) FILTER (WHERE tasks.status IS DISTINCT FROM '#{Task::STATUS_CANCELED}')"),
          Arel.sql(Task.sanitize_sql_array([
            "COUNT(*) FILTER (WHERE (tasks.status IS NULL OR tasks.status NOT IN (?, ?)) AND tasks.due_date < ?)",
            Task::STATUS_CLOSED, Task::STATUS_CANCELED, today
          ]))
        )
        .to_h { |id, done, total, overdue| [id, [done, total, overdue]] }
    end

    # Les actions rangées dans un groupe encore vivant du projet : c'est ce
    # que la page du projet affiche.
    def live_tasks(project_ids)
      Task.where(project_id: project_ids, bundle_id: Bundle.where(project_id: project_ids).select(:id))
    end

    def open_tasks(project_ids)
      live_tasks(project_ids)
        .where("tasks.status IS NULL OR tasks.status NOT IN (?)", [Task::STATUS_CLOSED, Task::STATUS_CANCELED])
    end
  end
end
