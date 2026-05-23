import { writeFile } from 'node:fs/promises'
import { mdxToMd } from 'mdx-to-md'
import { resolve } from 'node:path'
import remarkGfm from 'remark-gfm'
import remarkToc from 'remark-toc'

/**
 * @see https://github.com/kentcdodds/mdx-bundler?tab=readme-ov-file#mdxoptions
 */
function mdxOptions(options) {
  options.remarkPlugins = [
    ...(options.remarkPlugins ?? []),
    remarkGfm,
    remarkToc,
  ]

  return options
}

const args = process.argv.slice(2)
if (args.length === 0 || args.length % 2 !== 0) {
  console.error('Usage: node compile.js <src.mdx> <dst.md> [<src.mdx> <dst.md> ...]')
  process.exit(1)
}

for (let i = 0; i < args.length; i += 2) {
  const sourceRelativePath = args[i]
  const outputRelativePath = args[i + 1]
  const markdown = await mdxToMd(resolve(sourceRelativePath), { mdxOptions })
  const banner = `This markdown file was auto-generated from "${sourceRelativePath}"`
  const output = `<!--- ${banner} -->\n\n${markdown}`
  await writeFile(outputRelativePath, output)
  console.log(`📝 Converted ${sourceRelativePath} -> ${outputRelativePath}`)
}
