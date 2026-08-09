import { AppRouteRecord } from '@/types/router'
import { router } from '@/router'
import type { RouteLocationRaw } from 'vue-router'

type MenuJumpResult = boolean | Promise<unknown>
type MenuRouteCandidate = {
  location: RouteLocationRaw
}

export const openExternalLink = (link: string) => {
  const url = safeExternalLink(link)
  if (!url) return false
  window.open(url, '_blank', 'noopener,noreferrer')
  return true
}

export const safeExternalLink = (link: string) => {
  const value = link.trim()
  if (!value) return ''

  try {
    const url = new URL(value)
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return ''
    return url.toString()
  } catch {
    return ''
  }
}

const normalizeInternalPath = (path: string) => {
  if (!path) return ''
  if (/^https?:\/\//i.test(path)) return ''
  return path.startsWith('/') ? path : `/${path}`
}

const isNotFoundRoute = (resolved: ReturnType<typeof router.resolve>) => {
  return resolved.matched.some((record) => {
    return record.name === 'Exception404' || record.path.includes(':pathMatch')
  })
}

const resolveLocation = (candidate: MenuRouteCandidate) => {
  try {
    const resolved = router.resolve(candidate.location)
    if (resolved.matched.length === 0 || isNotFoundRoute(resolved)) {
      return null
    }

    return resolved
  } catch {
    return null
  }
}

const getMenuRouteCandidates = (item: AppRouteRecord): MenuRouteCandidate[] => {
  const candidates: MenuRouteCandidate[] = []

  const path = normalizeInternalPath(item.path)
  if (path) {
    candidates.push({ location: path })
  }

  if (item.name) {
    candidates.push({ location: { name: item.name } })
  }

  return candidates
}

const pushMenuRoute = (item: AppRouteRecord): MenuJumpResult => {
  const candidates = getMenuRouteCandidates(item)

  for (const candidate of candidates) {
    if (typeof candidate.location === 'string') {
      if (candidate.location === router.currentRoute.value.fullPath) {
        return false
      }

      return router.push(candidate.location).catch((error) => {
        console.error('[MenuJump] route jump failed:', error)
        return false
      })
    }

    const resolved = resolveLocation(candidate)
    if (!resolved) continue

    if (resolved.fullPath === router.currentRoute.value.fullPath) {
      return false
    }

    return router.push(resolved.fullPath).catch((error) => {
      console.error('[MenuJump] route jump failed:', error)
      return false
    })
  }

  console.warn('[MenuJump] route not found:', item.name || item.path || item.meta?.title)
  return false
}

const findFirstLeafMenu = (items: AppRouteRecord[]): AppRouteRecord | undefined => {
  for (const child of items) {
    if (child.meta.isHide) continue
    return child.children?.length ? findFirstLeafMenu(child.children) || child : child
  }

  return items[0]
}

export const handleMenuJump = (
  item: AppRouteRecord,
  jumpToFirst: boolean = false
): MenuJumpResult => {
  const { link, isIframe } = item.meta
  if (link && !isIframe) {
    return openExternalLink(link)
  }

  if (jumpToFirst && item.children?.length) {
    const firstChild = findFirstLeafMenu(item.children)
    return firstChild ? handleMenuJump(firstChild) : false
  }

  return pushMenuRoute(item)
}
