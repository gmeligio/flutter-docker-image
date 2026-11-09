const { existsSync, readFileSync } = require('node:fs') as typeof import('node:fs')

const COMMENT_LIMIT = 65536
const BOT_LOGIN = 'github-actions[bot]'

interface Comment {
  id: number
  body?: string
  user: { login: string } | null
}

interface Repo {
  owner: string
  repo: string
}

type Issue = Repo & { issue_number: number }

interface Args {
  github: {
    paginate(route: unknown, params: Issue & { per_page: number }): Promise<Comment[]>
    rest: {
      issues: {
        listComments: unknown
        createComment(params: Issue & { body: string }): Promise<unknown>
        updateComment(params: Repo & { comment_id: number; body: string }): Promise<unknown>
        deleteComment(params: Repo & { comment_id: number }): Promise<unknown>
      }
    }
  }
  context: {
    repo: Repo
    issue: { number: number }
    serverUrl: string
    runId: number
  }
  core: { warning(message: string): void }
}

function readReport(path: string): string {
  return existsSync(path) ? readFileSync(path, 'utf8').trim() : ''
}

function buildBody(marker: string, image: string, report: string, runUrl: string): string {
  const head = `${marker}\n### Docker Scout compare: ${image}\n\n`
  if (head.length + report.length <= COMMENT_LIMIT) return head + report

  const note = `\n\n_Report truncated. The full report is in the [workflow run](${runUrl})._`
  return head + report.slice(0, COMMENT_LIMIT - head.length - note.length) + note
}

module.exports = async ({ github, context, core }: Args): Promise<void> => {
  const image = process.env.IMAGE ?? ''
  const report = readReport(process.env.REPORT_FILE ?? '')
  if (!report) {
    core.warning(`No Docker Scout report for ${image}; its PR comment was not updated.`)
    return
  }

  const marker = `<!-- scout-compare:${image} -->`
  const { repo } = context
  const issue = { ...repo, issue_number: context.issue.number }
  const runUrl = `${context.serverUrl}/${repo.owner}/${repo.repo}/actions/runs/${context.runId}`
  const body = buildBody(marker, image, report, runUrl)

  const comments = await github.paginate(github.rest.issues.listComments, { ...issue, per_page: 100 })
  const [oldest, ...duplicates] = comments.filter(
    (comment) => comment.user?.login === BOT_LOGIN && comment.body?.startsWith(marker),
  )

  if (oldest) {
    await github.rest.issues.updateComment({ ...repo, comment_id: oldest.id, body })
  } else {
    await github.rest.issues.createComment({ ...issue, body })
  }

  for (const duplicate of duplicates) {
    await github.rest.issues.deleteComment({ ...repo, comment_id: duplicate.id })
  }
}
