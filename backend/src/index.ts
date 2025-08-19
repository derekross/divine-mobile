/**
 * NostrVine Backend - Cloudflare Workers
 * 
 * NIP-96 compliant file storage server with Cloudflare Stream integration
 * Supports vine-style video uploads, GIF conversion, and Nostr metadata broadcasting
 */

import { handleNIP96Info } from './handlers/nip96-info';
import { handleNIP96Upload, handleUploadOptions, handleJobStatus, handleMediaServing, handleThumbnailServing, handleVideoServing, handleReleaseDownload, handleVineUrlCompat } from './handlers/nip96-upload';
import { handleCloudinarySignedUpload, handleCloudinaryUploadOptions } from './handlers/cloudinary-upload';
import { handleCloudinaryWebhook, handleCloudinaryWebhookOptions } from './handlers/cloudinary-webhook';
import { handleVideoMetadata, handleVideoList, handleVideoMetadataOptions } from './handlers/video-metadata';

// New Cloudflare Stream handlers
import { handleStreamUploadRequest, handleStreamUploadOptions } from './handlers/stream-upload';
import { handleStreamWebhook, handleStreamWebhookOptions } from './handlers/stream-webhook';
import { handleVideoStatus, handleVideoStatusOptions } from './handlers/stream-status';

// Video caching API
import { handleVideoMetadata as handleVideoCacheMetadata, handleVideoMetadataOptions as handleVideoCacheOptions } from './handlers/video-cache-api';
import { handleBatchVideoLookup, handleBatchVideoOptions } from './handlers/batch-video-api';

// Analytics service
import { VideoAnalyticsService } from './services/analytics';
import { VideoAnalyticsEngineService } from './services/analytics-engine';
import { AnalyticsFallbackService } from './services/analytics-fallback';

// Thumbnail service
import { ThumbnailService } from './services/ThumbnailService';

// URL import handler
import { handleURLImport, handleURLImportOptions } from './handlers/url-import';

// Metadata API
import { handleGetFileMetadata, handleBatchGetMetadata, handleMetadataOptions } from './handlers/metadata-api';

// Feature flags
import {
  handleListFeatureFlags,
  handleGetFeatureFlag,
  handleCheckFeatureFlag,
  handleUpdateFeatureFlag,
  handleGradualRollout,
  handleRolloutHealth,
  handleRollback,
  handleFeatureFlagsOptions
} from './handlers/feature-flags-api';

// Moderation API
import { 
  handleReportSubmission, 
  handleModerationStatus, 
  handleModerationQueue, 
  handleModerationAction, 
  handleModerationOptions 
} from './handlers/moderation-api';

// NIP-05 Verification
import {
  handleNIP05Verification,
  handleNIP05Registration,
  handleNIP05Options
} from './handlers/nip05-verification';

// Cleanup script
import { handleCleanupRequest } from './scripts/cleanup-duplicates';

// Admin cleanup handler
import { handleAdminCleanup, handleAdminCleanupOptions } from './handlers/admin-cleanup';
import { handleAdminCleanupSimple, handleAdminCleanupSimpleOptions } from './handlers/admin-cleanup-simple';

// File check API
import { handleFileCheckBySha256, handleBatchFileCheck, handleFileCheckOptions } from './handlers/file-check';

// Analytics handlers (migrated from analytics-worker)
import { handleViewTracking } from './handlers/view-tracking';
import { handleTrending, handleVideoStats } from './handlers/trending';
import { handleTrendingVines } from './handlers/trending-vines';
import { handleTrendingViners } from './handlers/trending-viners';
import { handleHashtagTrending } from './handlers/hashtag-trending';
import { handleVelocityTrending } from './handlers/velocity-trending';
import { calculateTrending } from './services/trending-calculator';
import { handleAnalyticsCleanup } from './handlers/analytics-cleanup';
import { handleAggressiveAnalyticsCleanup } from './handlers/analytics-aggressive-cleanup';
import { handleTestAnalytics } from './handlers/test-analytics';
import type { AnalyticsEnv } from './types/analytics';

// Event mapping API
import { handleEventMapping, handleEventMappingOptions } from './handlers/event-mapping';

// Media lookup API
import { handleMediaLookup, handleMediaLookupOptions } from './handlers/media-lookup';

// KV stats handler
import { handleKVStats, handleKVStatsOptions } from './handlers/kv-stats';
import { handleKVQuickStats, handleKVQuickStatsOptions } from './handlers/kv-quick-stats';
import { handleKVCount, handleKVCountOptions } from './handlers/kv-count';

// Export Durable Object
export { UploadJobManager } from './services/upload-job-manager';

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url);
		const pathname = url.pathname;
		const method = request.method;
		
		// Request logging
		const startTime = Date.now();
		console.log(`🔍 ${method} ${pathname} from ${request.headers.get('origin') || 'unknown'}`);

		// Note: CORS preflight handling moved to individual endpoint handlers for proper functionality

		// Helper to wrap response with timing
		const wrapResponse = async (responsePromise: Promise<Response>): Promise<Response> => {
			const response = await responsePromise;
			const duration = Date.now() - startTime;
			console.log(`✅ ${method} ${pathname} - ${response.status} (${duration}ms)`);
			return response;
		};

		// Route handling
		try {
			// NIP-96 server information endpoint
			if (pathname === '/.well-known/nostr/nip96.json' && method === 'GET') {
				return wrapResponse(handleNIP96Info(request, env));
			}

			// NIP-05 verification endpoint
			if (pathname === '/.well-known/nostr.json' && method === 'GET') {
				return wrapResponse(handleNIP05Verification(request, env));
			}

			// NIP-05 registration endpoint
			if (pathname === '/api/nip05/register' && method === 'POST') {
				return wrapResponse(handleNIP05Registration(request, env));
			}

			if ((pathname === '/.well-known/nostr.json' || pathname === '/api/nip05/register') && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleNIP05Options()));
			}

			// Cloudflare Stream upload request endpoint (CDN implementation)
			if (pathname === '/v1/media/request-upload') {
				if (method === 'POST') {
					return handleStreamUploadRequest(request, env);
				}
				if (method === 'OPTIONS') {
					return handleStreamUploadOptions();
				}
			}

			// Cloudflare Stream webhook endpoint (CDN implementation)
			if (pathname === '/v1/webhooks/stream-complete') {
				if (method === 'POST') {
					return handleStreamWebhook(request, env, ctx);
				}
				if (method === 'OPTIONS') {
					return handleStreamWebhookOptions();
				}
			}

			// Video status polling endpoint
			if (pathname.startsWith('/v1/media/status/') && method === 'GET') {
				const videoId = pathname.split('/v1/media/status/')[1];
				return handleVideoStatus(videoId, request, env);
			}

			if (pathname.startsWith('/v1/media/status/') && method === 'OPTIONS') {
				return handleVideoStatusOptions();
			}


			// Video caching API endpoint
			if (pathname.startsWith('/api/video/') && method === 'GET') {
				const videoId = pathname.split('/api/video/')[1];
				return wrapResponse(handleVideoCacheMetadata(videoId, request, env, ctx));
			}

			if (pathname.startsWith('/api/video/') && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleVideoCacheOptions()));
			}

			// Batch video lookup endpoint
			if (pathname === '/api/videos/batch' && method === 'POST') {
				return wrapResponse(handleBatchVideoLookup(request, env, ctx));
			}

			if (pathname === '/api/videos/batch' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleBatchVideoOptions()));
			}

			// Analytics endpoints
			if (pathname === '/api/analytics/popular' && method === 'GET') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const url = new URL(request.url);
					const timeframe = url.searchParams.get('window') as '1h' | '24h' | '7d' || '24h';
					const limit = parseInt(url.searchParams.get('limit') || '10');
					
					const popularVideos = await analyticsEngine.getPopularVideos(timeframe, limit);
					
					return new Response(JSON.stringify({
						timeframe,
						videos: popularVideos,
						timestamp: new Date().toISOString()
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch popular videos' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Analytics view tracking endpoint
			if (pathname === '/analytics/view' && method === 'POST') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const data = await request.json() as any;
					
					// Extract video tracking data
					const { 
						eventId, 
						userId,
						source, 
						creatorPubkey, 
						hashtags, 
						title,
						eventType = 'view_start',
						watchDuration,
						totalDuration,
						loopCount,
						completedVideo
					} = data;
					
					if (!eventId) {
						return new Response(JSON.stringify({ error: 'eventId is required' }), {
							status: 400,
							headers: { 
								'Content-Type': 'application/json',
								'Access-Control-Allow-Origin': '*'
							}
						});
					}
					
					// Log incoming analytics data for debugging
					console.log('📊 Analytics request received:', {
						eventId: eventId?.substring(0, 8) + '...',
						userId: userId ? userId.substring(0, 8) + '...' : 'null',
						eventType,
						watchDuration,
						totalDuration,
						loopCount,
						completedVideo
					});
					
					// Calculate completion rate if durations are provided
					let completionRate = undefined;
					if (watchDuration && totalDuration) {
						completionRate = Math.min(watchDuration / totalDuration, 1.0);
					}
					
					// Track the video view using Analytics Engine
					await analyticsEngine.trackVideoView({
						videoId: eventId,
						userId: userId || undefined, // Now properly reading userId from mobile app
						creatorPubkey,
						source: source || 'mobile',
						eventType,
						hashtags,
						title,
						watchDuration,
						totalDuration,
						loopCount,
						completionRate
					}, request);
					
					return new Response(JSON.stringify({ 
						success: true,
						eventId,
						timestamp: new Date().toISOString()
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				} catch (error) {
					console.error('Analytics view tracking error:', error);
					return new Response(JSON.stringify({ error: 'Failed to track view' }), {
						status: 500,
						headers: { 
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				}
			}

			// OPTIONS handler for analytics view endpoint
			if (pathname === '/analytics/view' && method === 'OPTIONS') {
				return new Response(null, {
					status: 200,
					headers: {
						'Access-Control-Allow-Origin': '*',
						'Access-Control-Allow-Methods': 'POST, OPTIONS',
						'Access-Control-Allow-Headers': 'Content-Type, User-Agent',
						'Access-Control-Max-Age': '86400'
					}
				});
			}

			// Migrated analytics-worker endpoints
			// GET /analytics/trending/videos - Get trending videos (legacy endpoint)
			if (pathname === '/analytics/trending/videos' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleTrending(request, analyticsEnv));
			}

			// GET /analytics/trending/vines - Get trending vines (videos)
			if (pathname === '/analytics/trending/vines' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleTrendingVines(request, analyticsEnv, ctx));
			}

			// GET /analytics/trending/viners - Get trending viners (creators)
			if (pathname === '/analytics/trending/viners' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleTrendingViners(request, analyticsEnv));
			}

			// GET /analytics/video/:eventId/stats - Get video statistics
			const videoStatsMatch = pathname.match(/^\/analytics\/video\/([a-f0-9]{64})\/stats$/i);
			if (videoStatsMatch && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleVideoStats(request, analyticsEnv, videoStatsMatch[1]));
			}

			// GET /analytics/hashtag/:hashtag/trending - Get trending for specific hashtag
			const hashtagMatch = pathname.match(/^\/analytics\/hashtag\/([^\/]+)\/trending$/);
			if (hashtagMatch && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleHashtagTrending(request, analyticsEnv, hashtagMatch[1]));
			}

			// GET /analytics/hashtags/trending - Get trending hashtags
			if (pathname === '/analytics/hashtags/trending' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleHashtagTrending(request, analyticsEnv));
			}

			// GET /analytics/trending/velocity - Get rapidly ascending content
			if (pathname === '/analytics/trending/velocity' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleVelocityTrending(request, analyticsEnv));
			}

			// POST /analytics/refresh/trending - Background refresh of trending data (internal)
			if (pathname === '/analytics/refresh/trending' && method === 'POST') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				// Trigger background calculation without waiting
				calculateTrending(analyticsEnv).catch(e => console.error('Background trending calculation failed:', e));
				
				return new Response(
					JSON.stringify({ status: 'refresh_triggered' }),
					{
						status: 200,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					}
				);
			}
			
			// POST /analytics/cleanup - Clean up stale analytics data (protected)
			if (pathname === '/analytics/cleanup' && method === 'POST') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleAnalyticsCleanup(request, analyticsEnv));
			}

			// GET /analytics/cleanup/aggressive - Aggressive cleanup of ALL analytics data
			if (pathname === '/analytics/cleanup/aggressive' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return wrapResponse(handleAggressiveAnalyticsCleanup(request, analyticsEnv));
			}

			// GET /analytics/test - Test Analytics Engine writes
			if (pathname === '/analytics/test' && method === 'GET') {
				return wrapResponse(handleTestAnalytics(request, env));
			}

			// Analytics health check endpoint
			if (pathname === '/analytics/health' && method === 'GET') {
				const analyticsEnv = env as unknown as AnalyticsEnv;
				return new Response(
					JSON.stringify({
						status: 'healthy',
						environment: analyticsEnv.ENVIRONMENT || 'production',
						timestamp: new Date().toISOString(),
						// Future: could add KV connection status, etc.
					}),
					{
						status: 200,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					}
				);
			}

			// Video-specific analytics
			if (pathname.startsWith('/api/analytics/video/') && method === 'GET') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const videoId = pathname.split('/api/analytics/video/')[1];
					const url = new URL(request.url);
					const days = parseInt(url.searchParams.get('days') || '30');
					
					const videoAnalytics = await analyticsEngine.getVideoAnalytics(videoId, days);
					
					return new Response(JSON.stringify(videoAnalytics), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch video analytics' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Hashtag analytics
			if (pathname === '/api/analytics/hashtag' && method === 'GET') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const url = new URL(request.url);
					const hashtag = url.searchParams.get('hashtag');
					const days = parseInt(url.searchParams.get('days') || '7');
					
					if (!hashtag) {
						return new Response(JSON.stringify({ error: 'hashtag parameter is required' }), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}
					
					const hashtagAnalytics = await analyticsEngine.getHashtagAnalytics(hashtag, days);
					
					return new Response(JSON.stringify(hashtagAnalytics), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch hashtag analytics' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Creator analytics
			if (pathname === '/api/analytics/creator' && method === 'GET') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const url = new URL(request.url);
					const creatorPubkey = url.searchParams.get('pubkey');
					const days = parseInt(url.searchParams.get('days') || '30');
					
					if (!creatorPubkey) {
						return new Response(JSON.stringify({ error: 'pubkey parameter is required' }), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}
					
					const creatorAnalytics = await analyticsEngine.getCreatorAnalytics(creatorPubkey, days);
					
					return new Response(JSON.stringify(creatorAnalytics), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch creator analytics' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			if (pathname === '/api/analytics/dashboard' && method === 'GET') {
				try {
					// Use both analytics services - legacy for dashboard, engine for popular videos
					const analytics = new VideoAnalyticsService(env, ctx);
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					
					const [healthStatus, currentMetrics, popular24h] = await Promise.all([
						analytics.getHealthStatus(),
						analytics.getCurrentMetrics(),
						analyticsEngine.getPopularVideos('24h', 5)
					]);
					
					return new Response(JSON.stringify({
						health: healthStatus,
						metrics: currentMetrics,
						popularVideos: popular24h,
						timestamp: new Date().toISOString()
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=60'
						}
					});
				} catch (error) {
					console.error('Dashboard data fetch error:', error);
					return new Response(JSON.stringify({ 
						error: 'Failed to fetch dashboard data',
						message: error instanceof Error ? error.message : 'Unknown error'
					}), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Video social metrics endpoint
			if (pathname.startsWith('/api/analytics/video/') && pathname.endsWith('/social') && method === 'GET') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const videoId = pathname.split('/api/analytics/video/')[1].replace('/social', '');
					
					const socialMetrics = await analyticsEngine.getVideoSocialMetrics(videoId);
					
					return new Response(JSON.stringify(socialMetrics), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch video social metrics' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Batch video social metrics endpoint
			if (pathname === '/api/analytics/social/batch' && method === 'POST') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const { videoIds } = await request.json() as { videoIds: string[] };
					
					if (!videoIds || !Array.isArray(videoIds)) {
						return new Response(JSON.stringify({ error: 'videoIds array is required' }), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}

					// Limit batch size to prevent abuse
					if (videoIds.length > 50) {
						return new Response(JSON.stringify({ error: 'Maximum 50 video IDs allowed per batch' }), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}
					
					const batchSocialMetrics = await analyticsEngine.getBatchVideoSocialMetrics(videoIds);
					
					return new Response(JSON.stringify(batchSocialMetrics), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({ error: 'Failed to fetch batch social metrics' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// Social interaction tracking endpoint (for bot ingestion)
			if (pathname === '/api/analytics/social' && method === 'POST') {
				try {
					const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
					const data = await request.json() as {
						videoId: string;
						userId?: string;
						interactionType: 'like' | 'repost' | 'comment';
						nostrEventId: string;
						nostrEventKind: number;
						content?: string;
						timestamp?: number;
						creatorPubkey?: string;
					};
					
					const { videoId, userId, interactionType, nostrEventId, nostrEventKind, content, timestamp, creatorPubkey } = data;
					
					if (!videoId || !interactionType || !nostrEventId || !nostrEventKind) {
						return new Response(JSON.stringify({ 
							error: 'videoId, interactionType, nostrEventId, and nostrEventKind are required' 
						}), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}

					if (!['like', 'repost', 'comment'].includes(interactionType)) {
						return new Response(JSON.stringify({ 
							error: 'interactionType must be one of: like, repost, comment' 
						}), {
							status: 400,
							headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
						});
					}
					
					await analyticsEngine.trackSocialInteraction({
						videoId,
						userId,
						interactionType,
						nostrEventId,
						nostrEventKind,
						content,
						timestamp: timestamp || Date.now(),
						creatorPubkey
					}, request);
					
					return new Response(JSON.stringify({ 
						success: true,
						videoId,
						interactionType,
						timestamp: new Date().toISOString()
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				} catch (error) {
					console.error('Social interaction tracking error:', error);
					return new Response(JSON.stringify({ error: 'Failed to track social interaction' }), {
						status: 500,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
			}

			// OPTIONS handlers for social analytics endpoints
			if (((pathname.startsWith('/api/analytics/video/') && pathname.endsWith('/social')) || 
				pathname === '/api/analytics/social/batch' || 
				pathname === '/api/analytics/social') && method === 'OPTIONS') {
				return new Response(null, {
					status: 200,
					headers: {
						'Access-Control-Allow-Origin': '*',
						'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
						'Access-Control-Allow-Headers': 'Content-Type, Authorization',
						'Access-Control-Max-Age': '86400'
					}
				});
			}

			// File check endpoints - check if file exists before upload
			if (pathname.startsWith('/api/check/') && method === 'GET') {
				const sha256 = pathname.split('/api/check/')[1];
				return wrapResponse(handleFileCheckBySha256(sha256, request, env));
			}

			if (pathname === '/api/check' && method === 'POST') {
				return wrapResponse(handleBatchFileCheck(request, env));
			}

			if ((pathname === '/api/check' || pathname.startsWith('/api/check/')) && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleFileCheckOptions()));
			}

			// Metadata API endpoints
			if (pathname.startsWith('/api/metadata/') && pathname !== '/api/metadata/batch' && method === 'GET') {
				const fileId = pathname.split('/api/metadata/')[1];
				return wrapResponse(handleGetFileMetadata(fileId, env));
			}

			if (pathname === '/api/metadata/batch' && method === 'POST') {
				return wrapResponse(handleBatchGetMetadata(request, env));
			}

			if ((pathname === '/api/metadata/batch' || pathname.startsWith('/api/metadata/')) && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleMetadataOptions()));
			}

			// Event mapping endpoint
			if (pathname === '/api/event-mapping' && method === 'POST') {
				return wrapResponse(handleEventMapping(request, env));
			}

			if (pathname === '/api/event-mapping' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleEventMappingOptions()));
			}

			// Media lookup endpoint
			if (pathname === '/api/media/lookup' && method === 'GET') {
				return wrapResponse(handleMediaLookup(request, env, ctx));
			}

			if (pathname === '/api/media/lookup' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleMediaLookupOptions()));
			}

			// KV stats endpoint
			if (pathname === '/api/kv-stats' && method === 'GET') {
				return wrapResponse(handleKVStats(request, env));
			}
			
			if (pathname === '/api/kv-stats' && method === 'OPTIONS') {
				return handleKVStatsOptions();
			}
			
			if (pathname === '/api/kv-quick-stats' && method === 'GET') {
				return wrapResponse(handleKVQuickStats(request, env));
			}
			
			if (pathname === '/api/kv-quick-stats' && method === 'OPTIONS') {
				return handleKVQuickStatsOptions();
			}
			
			if (pathname === '/api/kv-count' && method === 'GET') {
				return wrapResponse(handleKVCount(request, env));
			}
			
			if (pathname === '/api/kv-count' && method === 'OPTIONS') {
				return handleKVCountOptions();
			}
			
			// Debug video metadata endpoint
			if (pathname === '/api/debug/video-metadata' && method === 'GET') {
				const url = new URL(request.url);
				const videoId = url.searchParams.get('videoId') || '1753764858668-00941579';
				
				const results: Record<string, any> = {};
				
				// Check different key patterns that might exist
				const keyPatterns = [
					`v1:video:${videoId}`,
					`video:${videoId}`,
					`${videoId}`,
					`file:${videoId}`,
					`metadata:${videoId}`
				];
				
				for (const key of keyPatterns) {
					try {
						const value = await env.METADATA_CACHE.get(key, 'json');
						results[key] = value || null;
					} catch (e) {
						results[key] = `Error: ${e.message}`;
					}
				}
				
				// Also check vine_id mapping
				try {
					const vineMapping = await env.METADATA_CACHE.get('vine_id:00941579178', 'json');
					results['vine_id:00941579178'] = vineMapping;
				} catch (e) {
					results['vine_id:00941579178'] = `Error: ${e.message}`;
				}
				
				return new Response(JSON.stringify(results, null, 2), {
					headers: {
						'Content-Type': 'application/json',
						'Access-Control-Allow-Origin': '*'
					}
				});
			}

			// Feature flag endpoints
			if (pathname === '/api/feature-flags' && method === 'GET') {
				return wrapResponse(handleListFeatureFlags(request, env, ctx));
			}

			if (pathname.startsWith('/api/feature-flags/') && pathname.endsWith('/check') && method === 'POST') {
				const flagName = pathname.split('/')[3];
				return wrapResponse(handleCheckFeatureFlag(flagName, request, env, ctx));
			}

			if (pathname.startsWith('/api/feature-flags/') && pathname.endsWith('/rollout') && method === 'POST') {
				const flagName = pathname.split('/')[3];
				return wrapResponse(handleGradualRollout(flagName, request, env, ctx));
			}

			if (pathname.startsWith('/api/feature-flags/') && pathname.endsWith('/health') && method === 'GET') {
				const flagName = pathname.split('/')[3];
				return wrapResponse(handleRolloutHealth(flagName, request, env, ctx));
			}

			if (pathname.startsWith('/api/feature-flags/') && pathname.endsWith('/rollback') && method === 'POST') {
				const flagName = pathname.split('/')[3];
				return wrapResponse(handleRollback(flagName, request, env, ctx));
			}

			if (pathname.startsWith('/api/feature-flags/') && !pathname.includes('/check') && !pathname.includes('/rollout') && !pathname.includes('/health') && !pathname.includes('/rollback')) {
				const flagName = pathname.split('/')[3];
				if (method === 'GET') {
					return wrapResponse(handleGetFeatureFlag(flagName, request, env, ctx));
				} else if (method === 'PUT') {
					return wrapResponse(handleUpdateFeatureFlag(flagName, request, env, ctx));
				}
			}

			if (pathname.startsWith('/api/feature-flags') && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleFeatureFlagsOptions()));
			}

			// Thumbnail endpoints
			if (pathname.startsWith('/thumbnail/') && method === 'GET') {
				const videoId = pathname.split('/thumbnail/')[1].split('?')[0];
				const thumbnailService = new ThumbnailService(env);
				
				// Parse query parameters
				const url = new URL(request.url);
				const options = {
					size: url.searchParams.get('size') as 'small' | 'medium' | 'large' | undefined,
					timestamp: parseInt(url.searchParams.get('t') || '1'),
					format: url.searchParams.get('format') as 'jpg' | 'webp' | undefined
				};
				
				return thumbnailService.getThumbnail(videoId, options);
			}

			if (pathname.startsWith('/thumbnail/') && pathname.endsWith('/upload') && method === 'POST') {
				const videoId = pathname.split('/thumbnail/')[1].split('/upload')[0];
				const thumbnailService = new ThumbnailService(env);
				
				// Get thumbnail data from request
				const formData = await request.formData();
				const thumbnailFile = formData.get('thumbnail');
				
				if (!thumbnailFile || !(thumbnailFile instanceof File)) {
					return new Response(JSON.stringify({ error: 'No thumbnail file provided' }), {
						status: 400,
						headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
					});
				}
				
				const thumbnailBuffer = await thumbnailFile.arrayBuffer();
				const format = thumbnailFile.type === 'image/webp' ? 'webp' : 'jpg';
				
				const thumbnailUrl = await thumbnailService.uploadCustomThumbnail(videoId, thumbnailBuffer, format);
				
				return new Response(JSON.stringify({ 
					success: true,
					thumbnailUrl 
				}), {
					headers: { 
						'Content-Type': 'application/json',
						'Access-Control-Allow-Origin': '*'
					}
				});
			}

			if (pathname.startsWith('/thumbnail/') && pathname.endsWith('/list') && method === 'GET') {
				const videoId = pathname.split('/thumbnail/')[1].split('/list')[0];
				const thumbnailService = new ThumbnailService(env);
				const thumbnails = await thumbnailService.listThumbnails(videoId);
				
				return new Response(JSON.stringify({
					videoId,
					thumbnails,
					count: thumbnails.length
				}), {
					headers: { 
						'Content-Type': 'application/json',
						'Access-Control-Allow-Origin': '*',
						'Cache-Control': 'public, max-age=300' // 5 minutes
					}
				});
			}

			if (pathname.startsWith('/thumbnail/') && method === 'OPTIONS') {
				return new Response(null, {
					status: 200,
					headers: {
						'Access-Control-Allow-Origin': '*',
						'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
						'Access-Control-Allow-Headers': 'Content-Type, Authorization'
					}
				});
			}

			// Video metadata endpoints
			if (pathname === '/v1/media/list' && method === 'GET') {
				return handleVideoList(request, env);
			}

			if (pathname.startsWith('/v1/media/metadata/') && method === 'GET') {
				const publicId = pathname.split('/v1/media/metadata/')[1];
				return handleVideoMetadata(publicId, request, env);
			}

			if (pathname === '/v1/media/list' && method === 'OPTIONS') {
				return handleVideoMetadataOptions();
			}

			if (pathname.startsWith('/v1/media/metadata/') && method === 'OPTIONS') {
				return handleVideoMetadataOptions();
			}


			// Releases download endpoint
			if (pathname.startsWith('/releases/')) {
				if (method === 'GET') {
					return handleReleaseDownload(pathname.substring(10), request, env);
				}
			}

			// Debug endpoint to list R2 bucket contents
			if (pathname === '/debug/r2-list' && method === 'GET') {
				try {
					const listResult = await env.MEDIA_BUCKET.list();
					return new Response(JSON.stringify({
						bucket: 'nostrvine-media',
						objects: listResult.objects?.map(obj => ({
							key: obj.key,
							size: obj.size,
							uploaded: obj.uploaded
						})) || [],
						truncated: listResult.truncated
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				} catch (error) {
					return new Response(JSON.stringify({
						error: 'Failed to list bucket',
						message: error.message
					}), {
						status: 500,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				}
			}

			// NIP-96 upload endpoint (compatibility)
			if (pathname === '/api/upload') {
				if (method === 'POST') {
					return handleNIP96Upload(request, env, ctx);
				}
				if (method === 'OPTIONS') {
					return handleUploadOptions();
				}
			}

			// URL import endpoint
			if (pathname === '/api/import-url') {
				if (method === 'POST') {
					return handleURLImport(request, env, ctx);
				}
				if (method === 'OPTIONS') {
					return handleURLImportOptions();
				}
			}

			// Upload job status endpoint
			if (pathname.startsWith('/api/status/') && method === 'GET') {
				const jobId = pathname.split('/api/status/')[1];
				return handleJobStatus(jobId, env);
			}

			// Set vine URL mapping endpoint for bulk importer
			if (pathname === '/api/set-vine-mapping' && method === 'POST') {
				try {
					const body = await request.json();
					const { vineUrlPath, fileId } = body;
					
					if (!vineUrlPath || !fileId) {
						return new Response(JSON.stringify({
							error: 'Missing parameters',
							message: 'Both vineUrlPath and fileId are required'
						}), {
							status: 400,
							headers: {
								'Content-Type': 'application/json',
								'Access-Control-Allow-Origin': '*'
							}
						});
					}

					if (!env.METADATA_CACHE) {
						return new Response(JSON.stringify({
							error: 'Metadata cache not available'
						}), {
							status: 503,
							headers: {
								'Content-Type': 'application/json',
								'Access-Control-Allow-Origin': '*'
							}
						});
					}

					const { MetadataStore } = await import('./services/metadata-store');
					const metadataStore = new MetadataStore(env.METADATA_CACHE);
					await metadataStore.setVineUrlMapping(vineUrlPath, fileId);

					return new Response(JSON.stringify({
						success: true,
						message: `Mapped ${vineUrlPath} to ${fileId}`
					}), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});

				} catch (error) {
					console.error('Set vine mapping error:', error);
					return new Response(JSON.stringify({
						error: 'Internal server error',
						message: error.message
					}), {
						status: 500,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				}
			}

			// Handle OPTIONS for set vine mapping
			if (pathname === '/api/set-vine-mapping' && method === 'OPTIONS') {
				return new Response(null, {
					status: 200,
					headers: {
						'Access-Control-Allow-Origin': '*',
						'Access-Control-Allow-Methods': 'POST, OPTIONS',
						'Access-Control-Allow-Headers': 'Content-Type, Authorization'
					}
				});
			}

			// Hash check endpoint for bulk importer
			if (pathname.startsWith('/api/check-hash/') && method === 'GET') {
				const sha256 = pathname.split('/api/check-hash/')[1];
				
				if (!sha256 || sha256.length !== 64) {
					return new Response(JSON.stringify({
						error: 'Invalid SHA256 hash',
						message: 'Provide a valid 64-character SHA256 hash'
					}), {
						status: 400,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				}

				try {
					if (!env.METADATA_CACHE) {
						return new Response(JSON.stringify({
							exists: false,
							error: 'Metadata cache not available'
						}), {
							status: 503,
							headers: {
								'Content-Type': 'application/json',
								'Access-Control-Allow-Origin': '*'
							}
						});
					}

					const { MetadataStore } = await import('./services/metadata-store');
					const metadataStore = new MetadataStore(env.METADATA_CACHE);
					const result = await metadataStore.checkDuplicateBySha256(sha256);

					if (!result) {
						return new Response(JSON.stringify({
							exists: false,
							error: 'Check failed'
						}), {
							status: 500,
							headers: {
								'Content-Type': 'application/json',
								'Access-Control-Allow-Origin': '*'
							}
						});
					}

					return new Response(JSON.stringify(result), {
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*',
							'Cache-Control': 'public, max-age=300' // 5 minutes cache
						}
					});

				} catch (error) {
					console.error('Hash check error:', error);
					return new Response(JSON.stringify({
						exists: false,
						error: 'Internal server error'
					}), {
						status: 500,
						headers: {
							'Content-Type': 'application/json',
							'Access-Control-Allow-Origin': '*'
						}
					});
				}
			}

			// Cleanup duplicates endpoint (admin only)
			if (pathname === '/admin/cleanup-duplicates' && method === 'POST') {
				return wrapResponse(handleCleanupRequest(request, env));
			}

			// Admin cleanup for corrupted HTML files
			if (pathname === '/admin/cleanup-html' && method === 'GET') {
				return wrapResponse(handleAdminCleanup(request, env));
			}
			
			if (pathname === '/admin/cleanup-html' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleAdminCleanupOptions()));
			}

			// Simple admin cleanup (by file size)
			if (pathname === '/admin/cleanup-simple' && method === 'GET') {
				return wrapResponse(handleAdminCleanupSimple(request, env));
			}
			
			if (pathname === '/admin/cleanup-simple' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleAdminCleanupSimpleOptions()));
			}

			// Analytics Dashboard (root path)
			if (pathname === '/' && method === 'GET') {
				const dashboardHtml = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenVine Analytics Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(45deg, #00ff87, #60efff);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .header p {
            opacity: 0.8;
            font-size: 1.1rem;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat-card {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .stat-card h3 {
            font-size: 2rem;
            color: #00ff87;
            margin-bottom: 10px;
        }
        
        .stat-card p {
            opacity: 0.8;
            font-size: 0.9rem;
        }
        
        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
        }
        
        .status.healthy {
            background: rgba(0, 255, 135, 0.2);
            color: #00ff87;
        }
        
        .status.unknown {
            background: rgba(255, 193, 7, 0.2);
            color: #ffc107;
        }
        
        .popular-videos {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 30px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            margin-bottom: 30px;
        }
        
        .popular-videos h2 {
            margin-bottom: 20px;
            color: #00ff87;
        }
        
        .video-list {
            display: grid;
            gap: 15px;
        }
        
        .video-item {
            background: rgba(255, 255, 255, 0.05);
            padding: 15px;
            border-radius: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .video-info h4 {
            margin-bottom: 5px;
        }
        
        .video-info p {
            opacity: 0.7;
            font-size: 0.9rem;
        }
        
        .video-stats {
            text-align: right;
        }
        
        .video-stats .views {
            color: #00ff87;
            font-weight: bold;
        }
        
        .video-preview {
            width: 80px;
            height: 80px;
            border-radius: 8px;
            overflow: hidden;
            background: rgba(0, 0, 0, 0.3);
            cursor: pointer;
            margin-right: 15px;
            flex-shrink: 0;
            position: relative;
        }
        
        .video-preview img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .video-preview .play-icon {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 30px;
            height: 30px;
            background: rgba(0, 0, 0, 0.7);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #00ff87;
        }
        
        .video-modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.9);
            z-index: 1000;
            align-items: center;
            justify-content: center;
        }
        
        .video-modal.active {
            display: flex;
        }
        
        .video-modal-content {
            position: relative;
            max-width: 90%;
            max-height: 90%;
        }
        
        .video-modal video {
            max-width: 100%;
            max-height: 80vh;
            border-radius: 10px;
        }
        
        .video-modal-close {
            position: absolute;
            top: -40px;
            right: 0;
            color: #fff;
            font-size: 2rem;
            cursor: pointer;
            background: none;
            border: none;
        }
        
        .refresh-btn {
            background: linear-gradient(45deg, #00ff87, #60efff);
            color: #1e3c72;
            border: none;
            padding: 12px 24px;
            border-radius: 25px;
            font-weight: bold;
            cursor: pointer;
            font-size: 1rem;
            margin: 20px auto;
            display: block;
            transition: transform 0.2s;
        }
        
        .refresh-btn:hover {
            transform: translateY(-2px);
        }
        
        .refresh-btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .endpoint-info {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 20px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            margin-top: 30px;
        }
        
        .endpoint-info h3 {
            color: #00ff87;
            margin-bottom: 15px;
        }
        
        .endpoint-list {
            display: grid;
            gap: 10px;
        }
        
        .endpoint {
            background: rgba(0, 0, 0, 0.2);
            padding: 10px 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
        }
        
        .loading {
            text-align: center;
            opacity: 0.7;
            font-style: italic;
        }
        
        .error {
            background: rgba(255, 0, 0, 0.2);
            color: #ff6b6b;
            padding: 15px;
            border-radius: 10px;
            margin: 10px 0;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 2rem;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .video-item {
                flex-direction: column;
                align-items: flex-start;
                gap: 10px;
            }
            
            .video-stats {
                text-align: left;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🍇 OpenVine Analytics</h1>
            <p>Real-time insights from your decentralized video platform</p>
        </div>
        
        <div class="stats-grid" id="statsGrid">
            <div class="stat-card">
                <h3 id="totalEvents">-</h3>
                <p>Total Events (5min)</p>
            </div>
            <div class="stat-card">
                <h3 id="activeVideos">-</h3>
                <p>Active Videos</p>
            </div>
            <div class="stat-card">
                <h3 id="activeUsers">-</h3>
                <p>Active Users</p>
            </div>
            <div class="stat-card">
                <h3 id="avgWatchTime">-</h3>
                <p>Avg Watch Time (ms)</p>
            </div>
        </div>
        
        <div id="systemStatus" class="stats-grid">
            <div class="stat-card">
                <h3>System Status</h3>
                <p>Analytics Engine: <span id="analyticsStatus" class="status">-</span></p>
                <p>R2 Storage: <span id="r2Status" class="status">-</span></p>
                <p>KV Storage: <span id="kvStatus" class="status">-</span></p>
            </div>
        </div>
        
        <div class="popular-videos">
            <h2>🔥 Popular Videos (24h)</h2>
            <div id="popularVideosList" class="video-list">
                <div class="loading">Loading popular videos...</div>
            </div>
        </div>
        
        <button class="refresh-btn" onclick="refreshDashboard()" id="refreshBtn">
            🔄 Refresh Data
        </button>
        
        <div class="endpoint-info">
            <h3>📡 Available Analytics Endpoints</h3>
            <div class="endpoint-list">
                <div class="endpoint">GET /api/analytics/dashboard - This dashboard data</div>
                <div class="endpoint">POST /analytics/view - Track video views</div>
                <div class="endpoint">GET /api/analytics/popular?window=24h&limit=10 - Popular videos</div>
                <div class="endpoint">GET /api/analytics/video/{videoId}?days=30 - Video-specific analytics</div>
                <div class="endpoint">GET /api/analytics/video/{videoId}/social - Video social metrics (likes, reposts, comments)</div>
                <div class="endpoint">POST /api/analytics/social/batch - Batch video social metrics</div>
                <div class="endpoint">POST /api/analytics/social - Track social interactions (for bot ingestion)</div>
                <div class="endpoint">GET /api/analytics/creator?pubkey={pubkey} - Creator analytics</div>
                <div class="endpoint">GET /api/analytics/hashtag?hashtag={tag} - Hashtag analytics</div>
            </div>
        </div>
        
        <div id="lastUpdate" style="text-align: center; margin-top: 20px; opacity: 0.6; font-size: 0.9rem;">
            Last updated: <span id="timestamp">-</span>
        </div>
    </div>
    
    <!-- Video Modal -->
    <div id="videoModal" class="video-modal" onclick="closeVideoModal(event)">
        <div class="video-modal-content" onclick="event.stopPropagation()">
            <button class="video-modal-close" onclick="closeVideoModal()">×</button>
            <video id="modalVideo" controls autoplay loop></video>
        </div>
    </div>
    
    <script>
        let refreshInterval;
        let currentVideos = [];
        
        async function fetchDashboardData() {
            try {
                // Use the same domain as the current page
                const baseUrl = window.location.origin;
                const response = await fetch(\`\${baseUrl}/api/analytics/dashboard\`);
                if (!response.ok) {
                    throw new Error(\`HTTP \${response.status}: \${response.statusText}\`);
                }
                return await response.json();
            } catch (error) {
                console.error('Failed to fetch dashboard data:', error);
                throw error;
            }
        }
        
        async function fetchPopularVideos() {
            try {
                // Use the same domain as the current page
                const baseUrl = window.location.origin;
                const response = await fetch(\`\${baseUrl}/api/analytics/popular?window=24h&limit=10\`);
                if (!response.ok) {
                    throw new Error(\`HTTP \${response.status}: \${response.statusText}\`);
                }
                return await response.json();
            } catch (error) {
                console.error('Failed to fetch popular videos:', error);
                throw error;
            }
        }
        
        function updateStats(data) {
            const metrics = data.metrics || {};
            
            document.getElementById('totalEvents').textContent = metrics.totalEvents || 0;
            document.getElementById('activeVideos').textContent = metrics.activeVideos || 0;
            document.getElementById('activeUsers').textContent = metrics.activeUsers || 0;
            document.getElementById('avgWatchTime').textContent = Math.round(metrics.averageWatchTime || 0);
            
            // Update system status
            const health = data.health || {};
            const deps = health.dependencies || {};
            
            updateStatusBadge('analyticsStatus', deps.analyticsEngine || 'unknown');
            updateStatusBadge('r2Status', deps.r2 || 'unknown');
            updateStatusBadge('kvStatus', deps.kv || 'unknown');
            
            // Update timestamp
            document.getElementById('timestamp').textContent = new Date(data.timestamp).toLocaleString();
        }
        
        function updateStatusBadge(elementId, status) {
            const element = document.getElementById(elementId);
            element.textContent = status;
            element.className = \`status \${status}\`;
        }
        
        function updatePopularVideos(data) {
            const container = document.getElementById('popularVideosList');
            const videos = data.popularVideos || data.videos || [];
            currentVideos = videos; // Store for video playback
            
            if (videos.length === 0) {
                container.innerHTML = \`
                    <div class="loading">
                        No popular videos yet. Videos will appear here once analytics data is available.
                        <br><br>
                        Note: SQL queries are pending Cloudflare Analytics Engine API availability.
                    </div>
                \`;
                return;
            }
            
            container.innerHTML = videos.map((video, index) => \`
                <div class="video-item">
                    <div class="video-preview" onclick="playVideo('\${video.videoId}', \${index})">
                        <img src="https://api.openvine.co/thumbnail/\${video.videoId}?size=small" 
                             alt="Video thumbnail" 
                             onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 100 100%27%3E%3Crect width=%27100%27 height=%27100%27 fill=%27%23333%27/%3E%3Ctext x=%2750%27 y=%2750%27 text-anchor=%27middle%27 dy=%27.3em%27 fill=%27%23999%27 font-family=%27sans-serif%27%3E🍇%3C/text%3E%3C/svg%3E'">
                        <div class="play-icon">▶</div>
                    </div>
                    <div class="video-info">
                        <h4>\${video.title || video.videoId?.substring(0, 12) + '...' || 'Unknown Video'}</h4>
                        <p>Views: \${video.views || 0} • Unique: \${video.uniqueViewers || 0}</p>
                    </div>
                    <div class="video-stats">
                        <div class="views">\${video.views || 0} views</div>
                        <p>Avg: \${Math.round(video.avgWatchTime || 0)}ms</p>
                        <p>Loops: \${video.totalLoops || 0}</p>
                    </div>
                </div>
            \`).join('');
        }
        
        function showError(message) {
            const container = document.getElementById('popularVideosList');
            container.innerHTML = \`
                <div class="error">
                    ❌ Error: \${message}
                    <br><br>
                    Analytics Engine is deployed but SQL queries may not be available yet.
                </div>
            \`;
        }
        
        async function refreshDashboard() {
            const refreshBtn = document.getElementById('refreshBtn');
            refreshBtn.disabled = true;
            refreshBtn.textContent = '🔄 Refreshing...';
            
            try {
                // Fetch dashboard data and popular videos in parallel
                const [dashboardData, popularData] = await Promise.all([
                    fetchDashboardData(),
                    fetchPopularVideos()
                ]);
                
                updateStats(dashboardData);
                updatePopularVideos(dashboardData);
                
            } catch (error) {
                console.error('Dashboard refresh failed:', error);
                showError(error.message);
            } finally {
                refreshBtn.disabled = false;
                refreshBtn.textContent = '🔄 Refresh Data';
            }
        }
        
        // Video playback functions
        async function playVideo(videoId, index) {
            const modal = document.getElementById('videoModal');
            const videoElement = document.getElementById('modalVideo');
            const baseUrl = window.location.origin;
            
            // First, try to get the video URL from the media lookup API
            try {
                const response = await fetch(\`\${baseUrl}/api/media/lookup?vine_id=\${videoId}\`);
                if (response.ok) {
                    const data = await response.json();
                    if (data.media_url) {
                        videoElement.src = data.media_url;
                        modal.classList.add('active');
                        return;
                    }
                }
            } catch (error) {
                console.error('Media lookup failed:', error);
            }
            
            // Fallback: Try the direct media endpoint
            videoElement.src = \`\${baseUrl}/media/\${videoId}\`;
            modal.classList.add('active');
        }
        
        function closeVideoModal(event) {
            if (!event || event.target.id === 'videoModal') {
                const modal = document.getElementById('videoModal');
                const videoElement = document.getElementById('modalVideo');
                
                modal.classList.remove('active');
                videoElement.pause();
                videoElement.src = '';
            }
        }
        
        // Escape key handler
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                closeVideoModal();
            }
        });
        
        // Initial load
        refreshDashboard();
        
        // Auto-refresh every 30 seconds
        refreshInterval = setInterval(refreshDashboard, 30000);
        
        // Clean up interval when page is hidden
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                clearInterval(refreshInterval);
            } else {
                refreshInterval = setInterval(refreshDashboard, 30000);
                refreshDashboard(); // Refresh immediately when page becomes visible
            }
        });
    </script>
</body>
</html>`;

				return new Response(dashboardHtml, {
					headers: {
						'Content-Type': 'text/html',
						'Cache-Control': 'public, max-age=60'
					}
				});
			}

			// Health check endpoint with analytics
			if (pathname === '/health' && method === 'GET') {
				const analyticsEngine = new VideoAnalyticsEngineService(env, ctx);
				const healthStatus = await analyticsEngine.getHealthStatus();
				
				return wrapResponse(Promise.resolve(new Response(JSON.stringify({
					...healthStatus,
					version: '1.0.0',
					services: {
						nip96: 'active',
						r2_storage: healthStatus.dependencies.r2,
						stream_api: 'active',
						video_cache_api: 'active',
						kv_storage: healthStatus.dependencies.kv,
						rate_limiter: healthStatus.dependencies.rateLimiter
					}
				}), {
					headers: {
						'Content-Type': 'application/json',
						'Access-Control-Allow-Origin': '*'
					}
				})));
			}

			// Original Vine URL compatibility - serve files using original vine CDN paths
			// Handle various Vine URL patterns like:
			// /r/videos_h264high/, /r/videos/, /r/videos_h264low/, /r/thumbs/, /r/avatars/, /v/, /t/
			if ((pathname.startsWith('/r/') || pathname.startsWith('/v/') || pathname.startsWith('/t/')) && method === 'GET') {
				const vineUrlPath = pathname.substring(1); // Remove leading slash
				return wrapResponse(handleVineUrlCompat(vineUrlPath, request, env));
			}

			// Media serving endpoint
			if (pathname.startsWith('/media/') && method === 'GET') {
				const fileId = pathname.split('/media/')[1];
				return handleMediaServing(fileId, request, env);
			}

			// Thumbnail serving endpoint - ALWAYS serves images
			if (pathname.startsWith('/thumbnail/') && method === 'GET') {
				const fileId = pathname.split('/thumbnail/')[1].split('?')[0]; // Remove query params
				return handleThumbnailServing(fileId, request, env);
			}

			// Video serving endpoint - ALWAYS serves videos
			if (pathname.startsWith('/video/') && method === 'GET') {
				const fileId = pathname.split('/video/')[1];
				return handleVideoServing(fileId, request, env);
			}

			// Moderation API endpoints
			if (pathname === '/api/moderation/report' && method === 'POST') {
				return wrapResponse(handleReportSubmission(request, env, ctx));
			}

			if (pathname === '/api/moderation/report' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleModerationOptions()));
			}

			if (pathname.startsWith('/api/moderation/status/') && method === 'GET') {
				const videoId = pathname.split('/api/moderation/status/')[1];
				return wrapResponse(handleModerationStatus(videoId, request, env));
			}

			if (pathname.startsWith('/api/moderation/status/') && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleModerationOptions()));
			}

			if (pathname === '/api/moderation/queue' && method === 'GET') {
				return wrapResponse(handleModerationQueue(request, env));
			}

			if (pathname === '/api/moderation/queue' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleModerationOptions()));
			}

			if (pathname === '/api/moderation/action' && method === 'POST') {
				return wrapResponse(handleModerationAction(request, env, ctx));
			}

			if (pathname === '/api/moderation/action' && method === 'OPTIONS') {
				return wrapResponse(Promise.resolve(handleModerationOptions()));
			}

			// Default 404 response
			return new Response(JSON.stringify({
				error: 'Not Found',
				message: `Endpoint ${pathname} not found`,
				available_endpoints: [
					'/.well-known/nostr/nip96.json',
					'/.well-known/nostr.json?name=username (NIP-05 verification)',
					'/api/nip05/register (NIP-05 username registration)',
					'/v1/media/request-upload (Stream CDN)',
					'/v1/webhooks/stream-complete',
					'/v1/media/status/{videoId}',
					'/v1/media/list',
					'/v1/media/metadata/{publicId}',
					'/api/video/{videoId} (Video Cache API)',
					'/api/videos/batch (Batch Video Lookup)',
					'/analytics/view (Track Video Views)',
					'/api/analytics/popular (Popular Videos)',
					'/api/analytics/dashboard (Analytics Dashboard)',
					'/api/analytics/video/{videoId} (Video Analytics)',
					'/api/analytics/video/{videoId}/social (Video Social Metrics)',
					'/api/analytics/social/batch (Batch Social Metrics)',
					'/api/analytics/social (Track Social Interactions)',
					'/api/analytics/hashtag?hashtag={tag} (Hashtag Analytics)',
					'/api/analytics/creator?pubkey={pubkey} (Creator Analytics)',
					'/api/media/lookup (Media Lookup by vine_id or filename)',
					'/api/feature-flags (Feature Flag Management)',
					'/api/feature-flags/{flagName}/check (Check Feature Flag)',
					'/api/moderation/report (Report content)',
					'/api/moderation/status/{videoId} (Check moderation status)',
					'/api/moderation/queue (Admin: View moderation queue)',
					'/api/moderation/action (Admin: Take moderation action)',
					'/v1/media/cloudinary-upload (Legacy)',
					'/v1/media/webhook (Legacy)',
					'/api/upload (NIP-96)',
					'/api/import-url (Import video from URL)',
					'/api/status/{jobId}',
					'/api/check-hash/{sha256} (Check if file exists by hash)',
					'/api/metadata/{fileId} (Get file metadata including SHA-256)',
					'/api/metadata/batch (POST: Get metadata for multiple files)',
					'/api/set-vine-mapping (Set mapping from original Vine URL to fileId)',
					'/admin/cleanup-duplicates (Admin: Clean up duplicate files)',
					'/admin/cleanup-html?mode=scan (Admin: Scan for corrupted HTML files)',
					'/admin/cleanup-html?mode=delete (Admin: Delete corrupted HTML files)',
					'/r/videos_h264high/{vineId}, /r/videos/{vineId}, /v/{vineId}, /t/{vineId} (Vine URL compatibility)',
					'/thumbnail/{videoId} (Get/generate thumbnail)',
					'/thumbnail/{videoId}/upload (Upload custom thumbnail)',
					'/thumbnail/{videoId}/list (List available thumbnails)',
					'/health',
					'/media/{fileId}',
					'/releases/{filename} (Download app releases)'
				]
			}), {
				status: 404,
				headers: {
					'Content-Type': 'application/json',
					'Access-Control-Allow-Origin': '*'
				}
			});

		} catch (error) {
			const duration = Date.now() - startTime;
			console.error(`❌ ${method} ${pathname} - Error after ${duration}ms:`, error);
			
			// Structured error response
			const errorResponse = {
				error: 'Internal Server Error',
				message: error instanceof Error ? error.message : 'An unexpected error occurred',
				timestamp: new Date().toISOString(),
				path: pathname,
				method: method
			};

			if (env.ENVIRONMENT === 'development') {
				// Include stack trace in development
				errorResponse['stack'] = error instanceof Error ? error.stack : undefined;
			}
			
			return new Response(JSON.stringify(errorResponse), {
				status: 500,
				headers: {
					'Content-Type': 'application/json',
					'Access-Control-Allow-Origin': '*',
					'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
					'Access-Control-Allow-Headers': 'Content-Type, Authorization'
				}
			});
		}
	},
	
	// Scheduled handler for periodic cleanup tasks
	async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
		const analyticsEnv = env as unknown as AnalyticsEnv;
		
		console.log(`Running scheduled cleanup at ${new Date().toISOString()}`);
		
		try {
			// Create a fake request with auth header for the cleanup handler
			const cleanupRequest = new Request('https://api.openvine.co/analytics/cleanup', {
				method: 'POST',
				headers: {
					'Authorization': `Bearer ${analyticsEnv.CLEANUP_AUTH_TOKEN || 'default-cleanup-token'}`
				}
			});
			
			// Run the cleanup
			const response = await handleAnalyticsCleanup(cleanupRequest, analyticsEnv);
			const result = await response.json();
			
			console.log('Scheduled cleanup completed:', result);
			
			// Also trigger trending recalculation after cleanup
			calculateTrending(analyticsEnv).catch(e => console.error('Post-cleanup trending calculation failed:', e));
			
		} catch (error) {
			console.error('Scheduled cleanup failed:', error);
		}
	},
} satisfies ExportedHandler<Env>;
