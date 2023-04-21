Shader "Hidden/_Test_SDF_Shadow"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

		_SDFTex("SDF",3D) = "black" {}

		[Space(20)]
		[KeywordEnum(No, Sphere, Cone, Variant)]_Trace("Which Soft Shadow ?", Int) = 1
		[HideInInspector]_LightDistance("Light Distance", FLOAT) = 10000
		_ShadowHard("Shadow Hard", FLOAT) = 4
		_ConeAng("COne Angle Degree", FLOAT) = 8

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma shader_feature_local __ _TRACE_SPHERE _TRACE_CONE _TRACE_VARIANT

			#include "UnityCG.cginc"
			#include "Unity_SDF_Util.hlsl"

			sampler2D _MainTex;
			float4 _MainTex_ST;

			Texture3D _SDFTex;
			SamplerState sampler_SDFTex;

			half _LightDistance;
			half _ShadowHard;
			half _ConeAng;

			float3 _SDFExtents;
			float4x4 _world2SDF;
			#define TO_SDF_SPACE _world2SDF
			#define SDF_EXT _SDFExtents

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				half3 normal : NORMAL;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 samplePos : TEXCOORD1;
				half3 normal : NORMAL;
				float4 lightPos : TEXCOORD2;
			};

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				float4 pos_ws = mul(unity_ObjectToWorld, v.vertex);
				o.samplePos = mul(TO_SDF_SPACE, float4(pos_ws.xyz, 1)).xyz;

				float3 norm_ws = UnityObjectToWorldNormal(v.normal.xyz);
				o.normal = mul(TO_SDF_SPACE, float4(norm_ws.xyz, 1)).xyz;

				// only doing dir light here
				float3 lightPos_ws = pos_ws + _WorldSpaceLightPos0.xyz * _LightDistance;
				float3 lightPos_sdf = mul(TO_SDF_SPACE, float4(lightPos_ws.xyz, 1)).xyz;

				o.lightPos.xyz = lightPos_sdf.xyz;
				o.lightPos.w = dot(_WorldSpaceLightPos0.xyz, norm_ws);

                return o;
            }

			//////////////////////////////////////////////////////////////
			#define SAMPLES 16

			bool __CheckOutBound(float3 uvw) {
				return uvw.x < 0.0 || uvw.x > 1.0 || uvw.y < 0.0 || uvw.y > 1.0 || uvw.z < 0.0 || uvw.z > 1.0;
			}

			// original sphere trace implement
			float _TraceShadow_Original(float3 position, float3 lightPosition, float hard, float3 extOrScale)
			{
				float3 dir_vec = lightPosition - position;
				float toLightDistance = length(dir_vec);
				float3 direction = dir_vec / toLightDistance;

				//float3 direction = normalize(lightPosition - position);
				//float toLightDistance = length(lightPosition - position);

				float result = 0;
				float rayDistance = 0.01;
				float nearest = 9999;
				for (int i = 0; i < SAMPLES; i++)
				{
					float3 uvw = position + direction * rayDistance;
					if (__CheckOutBound(uvw)) {
						result = saturate(nearest);
						break;
					}

					float sceneDist = GetDistanceFromSDF(_SDFTex, sampler_SDFTex, uvw, extOrScale, 0);

					if (sceneDist <= 0.001) {
						// meaning the ray is on the edge or inside a shape
						result = 0;
						break;
					}
					if (rayDistance > toLightDistance) {
						// meaing the ray has trace pass the light, without hitting anything
						result = saturate(nearest);
						break;
					}

					nearest = min(nearest, hard * sceneDist / rayDistance);

					rayDistance += sceneDist;
				}

				return result;
			}

			#define DEG_2_RAD	0.01745329
			// UE implement ?? Page 33: https://advances.realtimerendering.com/s2015/DynamicOcclusionWithSignedDistanceFields.pdf
			// instead of devided by rayDistanceTraveled, its divided by cone radius
			float _TraceShadow_ConeTrace(float3 position, float3 lightPosition, float hard, float cone_ang_deg, float3 extOrScale)
			{
				float3 dir_vec = lightPosition - position;
				float toLightDistance = length(dir_vec);
				float3 direction = dir_vec / toLightDistance;

				//float3 direction = normalize(lightPosition - position);
				//float toLightDistance = length(lightPosition - position);

				float result = 0;
				float rayDistance = 0.001;
				float nearest = 9999;
				float cone_tan = tan(cone_ang_deg * 0.5 * DEG_2_RAD);
				for (int i = 0; i < SAMPLES; i++)
				{
					//float sceneDist = scene_sdf_2d_Sahdow(position + direction * rayDistance);
					float3 uvw = position + direction * rayDistance;

					if (__CheckOutBound(uvw)) {
						result = saturate(nearest);
						break;
					}

					float sceneDist = GetDistanceFromSDF(_SDFTex, sampler_SDFTex, uvw, extOrScale, 0.0);
					float cone_radius = cone_tan * rayDistance;

					if (sceneDist <= 0) {
						// meaning the ray is on the edge or inside a shape
						result = 0;
						break;
					}
					if (rayDistance > toLightDistance) {
						// meaing the ray has trace pass the light, without hitting anything
						result = saturate(nearest);
						break;
					}

					nearest = min(nearest, hard * sceneDist / cone_radius);

					rayDistance += sceneDist;
				}

				return result;
			}

			// soft shadow method from https://github.com/ZephyrL/DFAO-unity
			// basicly another variant of sphere trace, an extra step is taken, rayDist^2/maxDistAllow > d / t, then its taken as result
			float _TraceShadow_variant(float3 pos, float Penumbra, float3 extOrScale)
			{
				// currently directional light
				float result = 1.0f;
				float maxDistance = 5.0;
				//float3 dir = normalize(_WorldSpaceLightPos0.xyz);
				float3 dir = (_WorldSpaceLightPos0.xyz);
				//float3 dir = normalize(_WorldSpaceLightPos0.xyz - pos);
				float t = 0.01;
				[loop]
				while (t < maxDistance) {
					float3 uvw = pos + dir * t;
					float d = GetDistanceFromSDF(_SDFTex, sampler_SDFTex, uvw, extOrScale, 0.0);

					if (d < 0.001) {
						return t * t / maxDistance;
					}
					result = min(result, max(t * t / maxDistance, Penumbra * d / t));

					t += d;
				}
				return result;
			}
			//////////////////////////////////////////////////////////////

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
				half NoL = i.lightPos.w;

				float3 uvw = i.samplePos.xyz;
				float3 lPos = i.lightPos.xyz;

				float shadow = 1;
#if _TRACE_SPHERE
				shadow = _TraceShadow_Original(uvw, lPos, _ShadowHard, SDF_EXT);
#endif
#if _TRACE_CONE
				shadow = _TraceShadow_ConeTrace(uvw, lPos, _ShadowHard, _ConeAng, SDF_EXT);
#endif
#if _TRACE_VARIANT
				shadow = _TraceShadow_variant(uvw, SDF_EXT, _ShadowHard);
#endif
				return shadow * NoL;

                return col;
            }
            ENDCG
        }
    }
}
