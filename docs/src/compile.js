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
const sourceRelativePath = args[0]
const outputRelativePath = args[1]
const markdown = await mdxToMd(resolve(sourceRelativePath), {
  mdxOptions,
})
const banner = `This markdown file was auto-generated from "${sourceRelativePath}"`
const readme = `<!--- ${banner} -->\n\n${markdown}`

await writeFile(outputRelativePath, readme)

console.log(`📝 Converted ${sourceRelativePath} -> ${outputRelativePath}`)
