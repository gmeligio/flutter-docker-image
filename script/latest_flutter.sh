curl -s https://api.github.com/repos/flutter/flutter/tags | grep -oP '"name": "\K(.*)(?=")' | head -n 1

curl -s -H "Authorization: bearer YOUR_TOKEN" -d '
{
    "query": "query { search(query: \"example\", type: REPOSITORY, first: 20) { repositoryCount edges { node { ... on Repository { defaultBranchRef { target { ... on Commit { zipballUrl } }}}}}}}"
}
' https://api.github.com/graphql | jq -r '.data.search.edges[].node.defaultBranchRef.target.zipballUrl' | xargs -I{} curl -O {}

# gh api graphql --paginate --raw-field owner=stedolan --raw-field name=jq --raw-field query=$QUERY \
#  --jq '.data.repository.refs.nodes |  [.[] | if .target.target? then {name:.name, date:.target.target.committedDate} else {name:.name, date:.target.committedDate} end] | sort_by(.date) | [.[].name]'

# curl -s -H "Authorization: bearer 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" -d '{"query": "query GetLatestTags { repository(owner: \"flutter\", name: \"flutter\") { tags: refs(refPrefix: \"refs/tags/\", first: 10, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) { edges { node { version: name target { oid } } } } } }"}' https://api.github.com/graphql | jq '[.data.repository.tags.edges[].node] | map(select(.version|test("^(\\d+\\.)+\\d+(?!-)$"))) | .[0] | {version, commit: .target.oid}'

{"query": "query GetLatestTags { repository(owner: \"flutter\", name: \"flutter\") { tags: refs(refPrefix: \"refs/tags/\", first: 10, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) { edges { node { version: name target { oid } } } } } }"}
