const { readFileSync } = require('node:fs')

const COMMENT_LIMIT = 65536
const BOT_LOGIN = 'github-actions[bot]'

function buildBody(marker, image, report, runUrl) {
  const head = `${marker}\n### Docker Scout compare: ${image}\n\n`
  if (!report) return `${head}_No Docker Scout report for the latest run. See the [workflow run](${runUrl})._`
  if (head.length + report.length <= COMMENT_LIMIT) return head + report

  const note = `\n\n_Report truncated. The full report is in the [workflow run](${runUrl})._`
  return head + report.slice(0, COMMENT_LIMIT - head.length - note.length) + note
}

module.exports = async ({ github, context, core }) => {
  const image = process.env.IMAGE
  const report = readFileSync(process.env.REPORT_FILE, 'utf8').trim()
  if (!report) core.warning(`No Docker Scout report for ${image}.`)

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
  } else if (report) {
    await github.rest.issues.createComment({ ...issue, body })
  }

  for (const duplicate of duplicates) {
    await github.rest.issues.deleteComment({ ...repo, comment_id: duplicate.id })
  }
}
