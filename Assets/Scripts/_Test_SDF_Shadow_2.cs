using UnityEngine;

public class _Test_SDF_Shadow_2 : MonoBehaviour
{
    public Vector3 m_SDF_Center;
    public Vector3 m_SDF_Scale;

    public Renderer[] _SDFRenderers;

    private Matrix4x4 _parent_l2w;
    private Matrix4x4 _sdf_l2w;
    private Matrix4x4 _sdf_l2w_combined;
    private Matrix4x4 _sdf_l2w_combined_inv;

    private MaterialPropertyBlock _mpb = null;

    void OnEnable()
    {
        _mpb = new MaterialPropertyBlock();
    }

    void Update()
    {
        var trans = transform;

        // offset the sdf center by its extents
        var sdf_ext = new Vector3(m_SDF_Scale.x * .5f, m_SDF_Scale.y * .5f, m_SDF_Scale.z * .5f);
        var sdf_pos = Vector3.zero;
        sdf_pos.x = m_SDF_Center.x - sdf_ext.x;
        sdf_pos.y = m_SDF_Center.y - sdf_ext.y;
        sdf_pos.z = m_SDF_Center.z - sdf_ext.z;

        // combine the l2w from parent with the sdf_l2w, then inverse it --> w2sdf
        _parent_l2w = trans.localToWorldMatrix;
        _sdf_l2w = Matrix4x4.TRS(sdf_pos, Quaternion.identity, m_SDF_Scale);
        _sdf_l2w_combined = _parent_l2w * _sdf_l2w;
        _sdf_l2w_combined_inv = _sdf_l2w_combined.inverse;

        var count = _SDFRenderers.Length;
        if (count < 1) return;
        _mpb.Clear();
        _mpb.SetMatrix("_world2SDF", _sdf_l2w_combined_inv);
        _mpb.SetVector("_SDFExtents", new Vector4(sdf_ext.x, sdf_ext.y, sdf_ext.z, 0));
        for (var i = 0; i < count; i++)
        {
            var raRend = _SDFRenderers[i];
            if (raRend == null) continue;
            raRend.SetPropertyBlock(_mpb);
        }
    }
}
