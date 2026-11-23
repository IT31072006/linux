import re
import os
import subprocess
import markdown

SOURCE_MD = "/home/tmthang/linux/BAO_CAO_DO_AN_DEVOPS_LINUX.md"
OUTPUT_HTML = "/tmp/bao_cao_do_an.html"
OUTPUT_PDF = "/home/tmthang/linux/BAO_CAO_DO_AN_DEVOPS_LINUX.pdf"

with open(SOURCE_MD, "r", encoding="utf-8") as f:
    text = f.read()

# Replace <pagebreak/> with page-break div
text = text.replace("<pagebreak/>", '<div class="page-break"></div>')

# Handle mermaid code blocks so markdown doesn't wrap them in code tags
# Replace ```mermaid ... ``` with <pre class="mermaid"> ... </pre>
def replace_mermaid(match):
    code = match.group(1).strip()
    return f'<div class="mermaid-container"><pre class="mermaid">\n{code}\n</pre></div>'

text = re.sub(r'```mermaid\s*\n(.*?)\n```', replace_mermaid, text, flags=re.DOTALL)

# Convert Markdown to HTML
html_content = markdown.markdown(
    text,
    extensions=[
        'tables',
        'fenced_code',
        'toc',
        'sane_lists'
    ]
)

html_document = f"""<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <title>Báo Cáo Đồ Án: Configure and Deploy DevOps Services in Linux</title>
  
  <!-- Math KaTeX -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js"
          onload="renderMathInElement(document.body, {{
            delimiters: [
              {{left: '$$', right: '$$', display: true}},
              {{left: '$', right: '$', display: false}}
            ]
          }});"></script>

  <!-- Mermaid Diagrams -->
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script>
    mermaid.initialize({{
      startOnLoad: true,
      theme: 'default',
      securityLevel: 'loose',
      fontFamily: '"Times New Roman", Times, serif'
    }});
  </script>

  <style>
    @page {{
      size: A4;
      margin: 20mm 15mm 20mm 25mm; /* Left margin 25mm for thesis binding */
      @bottom-right {{
        content: counter(page);
        font-size: 10pt;
        font-family: "Times New Roman", Times, serif;
      }}
    }}

    body {{
      font-family: "Times New Roman", Times, "Liberation Serif", serif;
      font-size: 12.5pt;
      line-height: 1.45;
      color: #111827;
      background-color: #ffffff;
      margin: 0;
      padding: 0;
      text-align: justify;
    }}

    .page-break {{
      page-break-after: always;
      break-after: page;
      clear: both;
    }}

    h1, h2, h3, h4, h5, h6 {{
      font-family: "Times New Roman", Times, "Liberation Serif", serif;
      font-weight: bold;
      color: #0f172a;
      break-after: avoid;
      page-break-after: avoid;
    }}

    h1 {{
      font-size: 18pt;
      margin-top: 24pt;
      margin-bottom: 14pt;
      text-align: center;
      line-height: 1.3;
    }}

    h2 {{
      font-size: 15pt;
      margin-top: 18pt;
      margin-bottom: 10pt;
      border-bottom: 1.5px solid #cbd5e1;
      padding-bottom: 4pt;
      color: #1e293b;
    }}

    h3 {{
      font-size: 13.5pt;
      margin-top: 14pt;
      margin-bottom: 8pt;
      color: #334155;
    }}

    h4 {{
      font-size: 12.5pt;
      margin-top: 10pt;
      margin-bottom: 6pt;
    }}

    p {{
      margin-top: 0;
      margin-bottom: 8pt;
      text-indent: 1.5em;
    }}

    /* Remove text indent for headings, lists, tables, code, center div */
    div, table, pre, blockquote, ul, ol {{
      text-indent: 0;
    }}

    ul, ol {{
      margin-top: 0;
      margin-bottom: 8pt;
      padding-left: 28pt;
    }}

    li {{
      margin-bottom: 4pt;
    }}

    table {{
      width: 100%;
      border-collapse: collapse;
      margin: 14pt 0;
      font-size: 10.5pt;
      page-break-inside: avoid;
      break-inside: avoid;
    }}

    th, td {{
      border: 1px solid #94a3b8;
      padding: 6pt 8pt;
      text-align: left;
      vertical-align: top;
    }}

    th {{
      background-color: #f1f5f9;
      color: #0f172a;
      font-weight: bold;
      text-align: center;
    }}

    tr:nth-child(even) {{
      background-color: #f8fafc;
    }}

    pre {{
      background: #f8fafc;
      border: 1px solid #cbd5e1;
      border-left: 4px solid #2563eb;
      border-radius: 4px;
      padding: 8pt 10pt;
      font-family: "Courier New", Courier, monospace;
      font-size: 9.5pt;
      line-height: 1.35;
      overflow-x: auto;
      page-break-inside: avoid;
      break-inside: avoid;
      white-space: pre-wrap;
      word-break: break-all;
    }}

    code {{
      font-family: "Courier New", Courier, monospace;
      font-size: 10pt;
      background: #f1f5f9;
      padding: 1pt 3pt;
      border-radius: 2pt;
      color: #0969da;
    }}

    pre code {{
      background: transparent;
      padding: 0;
      color: inherit;
    }}

    .mermaid-container {{
      display: flex;
      justify-content: center;
      margin: 14pt 0;
      page-break-inside: avoid;
      break-inside: avoid;
      text-align: center;
    }}

    .mermaid {{
      text-align: center;
    }}

    .mermaid svg {{
      max-width: 95% !important;
      height: auto !important;
    }}

    blockquote {{
      border-left: 4px solid #0284c7;
      background: #f0f9ff;
      margin: 10pt 0;
      padding: 6pt 12pt;
      font-style: italic;
      color: #0369a1;
      page-break-inside: avoid;
    }}

    hr {{
      border: 0;
      height: 1px;
      background: #cbd5e1;
      margin: 16pt 0;
    }}
  </style>
</head>
<body>
{html_content}
</body>
</html>
"""

with open(OUTPUT_HTML, "w", encoding="utf-8") as f:
    f.write(html_document)

print(f"Generated HTML: {OUTPUT_HTML} ({os.path.getsize(OUTPUT_HTML)} bytes)")
