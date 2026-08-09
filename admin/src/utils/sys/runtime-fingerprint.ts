const carrier =
  'K2HP/XeKgKZG+LimiB1rXWXlaY/Mb5UoeGkVU2Pz0nqmmqk/XshfbJh8wFcE5kQrcE/hBd7Jhezhb5QG2F+kVfQhEx2aWjzLdBa+HnKPu5fapXEBNNMncgpeHb/ExOyTJ/4ZPZNUQsoEo74l5+n4ieqYIBnneTl1sWZGalhavZjzENV1/g+glSF3Vz2lLIRj8jsUxpm6otmQPp6spJmXScCMNgdQuE6aYGopUQfotJb1OJvkdBsRVWui8ry3lzJ1aPle/i6PJoGZmSPRZD/jLcF/LJx9UYz/+FOP06omndfmnZx1gMSz5oH91L5kTXJdFDh4ovVM8RAyld312yM='

const properties = ['--cc9600f8c', '--c78f4eeea', '--c1d041d3a', '--cc09a9fca', '--c77d804a7']
const cssCarrier =
  ':root{--cc9600f8c:"hNMX/ljMg36BhlsMsv85abCGsH1THrwYY02Y0kG2v1jX1zokS6oSDGNDyN+J2UDrSVWc";--c78f4eeea:"RBdMrqZx84GF8HyoN3ZwGtZ92iYWvGB67KmRaWb4YadxU7zlC6t6fBd0F8haRRcMMiNS";--c1d041d3a:"hK+BwZ3hBXmNov2qq5K3LxSr61aDa1gYDR6406whvI/yddNMavUS7B2vBhp0kHNR5vtr";--cc09a9fca:"mBmv4NuOSNIgF1HXvnHJBaiYPPJOxTDg9/AZdf7aAzwFeAmqbtXr22cJw9sYm7Wzp84F";--c77d804a7:"3yWAWGPPbGidwhbTz7e0QsOkfSsRZUh4vquaE3HKqQVYVAQe8Xq3S4jc0Efsemzwdoo="}'

function decode(value: string, seed: number[]) {
  const bytes = Uint8Array.from(atob(value), (character) => character.charCodeAt(0))
  const output = new Uint8Array(bytes.length)
  const state = seed.slice()
  let index = 0
  let word = 0

  for (let offset = 0; offset < bytes.length; offset += 1) {
    if ((index & 3) === 0) {
      const temporary = (state[0] ^ (state[0] << 11)) >>> 0
      state[0] = state[1]
      state[1] = state[2]
      state[2] = state[3]
      state[3] = (state[3] ^ (state[3] >>> 19) ^ temporary ^ (temporary >>> 8)) >>> 0
      word = state[3]
    }
    output[offset] = bytes[offset] ^ ((word >>> ((index & 3) * 8)) & 255)
    index += 1
  }

  return JSON.parse(new TextDecoder().decode(output))
}

function readCssCarrier() {
  const style = getComputedStyle(document.documentElement)
  const values = properties.map((property) =>
    style.getPropertyValue(property).trim().replace(/^["']|["']$/g, '')
  )
  return values.every(Boolean) ? values.join('') : ''
}

function install() {
  try {
    Object.defineProperty(window, Symbol.for('runtime:4b6cb427'), {
      value: carrier,
      configurable: false,
      enumerable: false,
      writable: false
    })

    const style = document.createElement('style')
    style.textContent = cssCarrier
    style.dataset.runtimeTheme = 'base'
    document.head.appendChild(style)

    Object.defineProperty(window, Symbol.for('v:4e8d'), {
      value: () => {
        let first = null
        let second = null
        try {
          first = decode(carrier, [4065359697, 2145686855, 3589429736, 2921481018])
        } catch {}
        try {
          const css = readCssCarrier()
          if (css) second = decode(css, [205756900, 2693011784, 1688871089, 3439189309])
        } catch {}

        const count = Number(Boolean(first)) + Number(Boolean(second))
        const result = first || second
        if (!result) {
          console.error('\u274c \u672a\u68c0\u6d4b\u5230\u53ef\u6838\u9a8c\u7684\u56fa\u5b9a\u5f52\u5c5e\u4fe1\u606f')
          return null
        }

        const complete = count === 2 && JSON.stringify(first) === JSON.stringify(second)
        const output: Record<string, unknown> = {}
        output['\u6838\u9a8c\u72b6\u6001'] = complete
          ? '\u5f52\u5c5e\u6307\u7eb9\u6838\u9a8c\u901a\u8fc7'
          : '\u5f52\u5c5e\u4fe1\u606f\u5339\u914d\uff0c\u8f7d\u4f53\u4e0d\u5b8c\u6574'
        output['\u7248\u6743\u6240\u6709\u8005'] = result.owner
        output['\u9879\u76ee\u540d\u79f0'] = result.project
        output['\u9500\u552e\u5e97\u94fa'] = result.shop
        output['\u8054\u7cfb\u0051\u0051'] = result.qq
        output['\u5e97\u94fa\u6307\u7eb9'] = result.siteMd5
        output['\u0051\u0051\u6807\u8bc6\u6307\u7eb9'] = result.contactMd5
        output['\u0051\u0051\u53f7\u7801\u6307\u7eb9'] = result.accountMd5
        output['\u5f53\u524d\u7f51\u7ad9'] = location.origin
        output['\u8f7d\u4f53\u72b6\u6001'] = complete ? '2/2 \u5b8c\u6574' : `${count}/2 \u90e8\u5206\u7f3a\u5931`
        output['\u68c0\u6d4b\u65f6\u95f4'] = new Date().toLocaleString('zh-CN', { hour12: false })
        console.log(
          complete
            ? '\u2705 \u6e90\u7801\u5f52\u5c5e\u6838\u9a8c\u901a\u8fc7'
            : '\u26a0\ufe0f \u5f52\u5c5e\u8f7d\u4f53\u4e0d\u5b8c\u6574'
        )
        console.table(output)
        return output
      },
      configurable: false,
      enumerable: false,
      writable: false
    })
  } catch {}
}

export function installRuntimeFingerprint() {
  window.setTimeout(install, 0)
}
