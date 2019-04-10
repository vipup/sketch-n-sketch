## mostly duplicating littleReader.py
import io

def trimNewline(s): return s[:-1]
def write(f, s): f.write(s)
def writeLn(f, s): f.write(s + u'\n')

def readLeo(name, folder='../examples/'):
  f = folder + name + u'.elm'

  # e.g. LEO_TO_ELM fromleo/markdown ---> fromleo_markdown = ...
  name = name.replace(u'/', u'_')

  ## yield (name + ' = \"\n')
  ## following version is to facilitate line/col numbers:
  yield (name + u' =\n \"\"\"')

  for s in io.open(f,encoding="utf8"):
    s = s.replace(u'\\',u'\\\\')
    s = s.replace(u'\"',u'\\\"')
    yield s

  yield (u'\n\"\"\"\n\n')