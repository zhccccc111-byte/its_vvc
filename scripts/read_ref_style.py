#!/usr/bin/env python3
"""Read styles from reference docx template - raw XML."""
import zipfile

path = r'D:\Workspace\its_vvc\doc\ref_template.docx'
zf = zipfile.ZipFile(path)

# Read styles.xml - full content
styles_xml = zf.read('word/styles.xml').decode('utf-8')
print("=== styles.xml (full) ===")
print(styles_xml)
