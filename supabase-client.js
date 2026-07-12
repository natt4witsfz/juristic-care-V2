(function () {
  const config = window.JURISTIC_CONFIG || {};
  const AUTH_DOMAIN = "auth.juristic.local";
  const BUCKETS = {
    jobAttachments: "job-attachments",
    announcementFiles: "announcement-files",
    profileImages: "profile-images"
  };

  let client = null;

  function isEnabled() {
    return !!(
      config.SUPABASE_ENABLED &&
      config.SUPABASE_URL &&
      config.SUPABASE_ANON_KEY &&
      window.supabase?.createClient
    );
  }

  function getClient() {
    if (!isEnabled()) return null;
    if (!client) {
      client = window.supabase.createClient(config.SUPABASE_URL, config.SUPABASE_ANON_KEY, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true
        }
      });
    }
    return client;
  }

  function normalizeLoginId(loginId = "") {
    return String(loginId).trim().toLowerCase();
  }

  function loginIdToEmail(loginId = "") {
    const normalized = normalizeLoginId(loginId)
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return `${normalized || "user"}@${AUTH_DOMAIN}`;
  }

  function appUserFromRecord(record = {}) {
    const firstName = record.first_name || "";
    const lastName = record.last_name || "";
    const displayName = record.display_name || [firstName, lastName].filter(Boolean).join(" ").trim();
    const role = record.app_role || record.role || "resident";
    const department = record.department || (role === "resident" ? "resident" : "juristic");
    return {
      id: record.id || record.auth_user_id,
      authUserId: record.auth_user_id,
      firstName,
      lastName,
      name: displayName,
      enName: record.en_name || displayName,
      nickName: record.nickname || "",
      position: record.position || "",
      department,
      room: record.login_id || record.room_no || "",
      roomId: record.room_id || "",
      role,
      roleKey: record.role_key || `role.${role}`,
      isCoAdmin: !!record.is_co_admin || role === "coadmin",
      assignL1: !!record.assign_l1,
      assignL2: !!record.assign_l2,
      canAssign: !!record.can_assign,
      permissions: record.permissions || {},
      profileImage: record.profile_image_path || "",
      phone: record.phone || "",
      isSupabaseUser: true
    };
  }

  async function signIn(loginId, password) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const email = loginIdToEmail(loginId);
    const { error } = await supabaseClient.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return loadCurrentUserContext();
  }

  async function signOut() {
    const supabaseClient = getClient();
    if (!supabaseClient) return;
    await supabaseClient.auth.signOut();
  }

  async function loadCurrentUserContext() {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data: authData, error: authError } = await supabaseClient.auth.getUser();
    if (authError) throw authError;
    const authUserId = authData?.user?.id;
    if (!authUserId) return null;
    const { data, error } = await supabaseClient
      .from("app_users")
      .select("*")
      .eq("auth_user_id", authUserId)
      .eq("is_active", true)
      .maybeSingle();
    if (error) throw error;
    return data ? appUserFromRecord(data) : null;
  }

  async function loadAppData() {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("get_app_bootstrap");
    if (error) throw error;
    return data || null;
  }

  // Stage 3 canonical job read path. list_jobs_for_current_user() is the only
  // supported client job read: RLS-filtered via can_read_job, relational
  // columns authoritative, no PIN material. Uses the anon (publishable) key +
  // the caller's session only.
  async function listJobs() {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("list_jobs_for_current_user");
    if (error) throw error;
    return Array.isArray(data) ? data : [];
  }

  async function saveSnapshot(snapshot) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("save_client_snapshot", {
      p_snapshot: snapshot
    });
    if (error) throw error;
    return data;
  }

  async function createJob(payload) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("create_job", { p_payload: payload });
    if (error) throw error;
    return data;
  }

  async function assignJob(jobId, assigneeId, extra = {}) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("assign_job", {
      p_job_id: jobId,
      p_assignee_id: assigneeId,
      p_extra: extra
    });
    if (error) throw error;
    return data;
  }

  async function updateJobStatus(jobId, payload) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("update_job_status", {
      p_job_id: jobId,
      p_payload: payload
    });
    if (error) throw error;
    return data;
  }

  async function verifyCompletion(jobId) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("verify_job_completion", {
      p_job_id: jobId
    });
    if (error) throw error;
    return data;
  }

  async function listLogs() {
    const data = await loadAppData();
    return {
      adminLogs: data?.adminLogs || [],
      staffLogs: data?.staffLogs || [],
      residentLogs: data?.residentLogs || []
    };
  }

  async function savePermissions(userId, permissions) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient
      .from("permissions")
      .upsert({
        user_id: userId,
        sidebar: permissions?.sidebar || {},
        actions: permissions?.actions || {}
      })
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async function saveSidebarOrder(userId, orderedKeys) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient
      .from("sidebar_preferences")
      .upsert({
        user_id: userId,
        ordered_keys: orderedKeys || []
      })
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async function listAccountProfiles() {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("list_account_profiles");
    if (error) throw error;
    return Array.isArray(data) ? data : [];
  }

  async function createAccountProfile(profileType, displayName, roomNumber = "") {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("create_account_profile", {
      p_profile_type: profileType,
      p_display_name: displayName,
      p_room_number: roomNumber
    });
    if (error) throw error;
    return data;
  }

  async function selectAccountProfile(profileId) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("select_account_profile", {
      p_profile_id: profileId
    });
    if (error) throw error;
    return data;
  }

  async function issueProfilePinChallenge(profileId, sessionId) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("issue_profile_pin_challenge", {
      p_profile_id: profileId,
      p_session_id: sessionId
    });
    if (error) throw error;
    return data;
  }

  async function verifyProfilePinChallenge(profileId, sessionId, pin) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("verify_profile_pin_challenge", {
      p_profile_id: profileId,
      p_session_id: sessionId,
      p_pin: pin
    });
    if (error) throw error;
    return data;
  }

  async function saveInterfacePreference(profileId, interfaceMode) {
    const supabaseClient = getClient();
    if (!supabaseClient) return null;
    const { data, error } = await supabaseClient.rpc("save_interface_preference", {
      p_profile_id: profileId,
      p_interface_mode: interfaceMode
    });
    if (error) throw error;
    return data;
  }

  function safeFileName(name = "file") {
    return String(name)
      .normalize("NFKD")
      .replace(/[^\w.\-]+/g, "-")
      .replace(/-+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 120) || "file";
  }

  async function uploadFile(bucket, file, options = {}) {
    const supabaseClient = getClient();
    if (!supabaseClient || !file) return null;
    const folder = options.folder || "general";
    const prefix = options.prefix || crypto.randomUUID?.() || String(Date.now());
    const path = `${folder}/${prefix}-${safeFileName(file.name)}`;
    const { data, error } = await supabaseClient.storage
      .from(bucket)
      .upload(path, file, {
        cacheControl: "3600",
        upsert: false,
        contentType: file.type || "application/octet-stream"
      });
    if (error) throw error;
    return {
      bucket,
      path: data.path,
      mimeType: file.type || "",
      size: file.size || 0,
      originalName: file.name || ""
    };
  }

  async function uploadJobAttachment(file, jobId = "draft") {
    return uploadFile(BUCKETS.jobAttachments, file, { folder: `jobs/${jobId}` });
  }

  async function uploadAnnouncementFile(file, announcementId = "draft") {
    return uploadFile(BUCKETS.announcementFiles, file, { folder: `announcements/${announcementId}` });
  }

  async function uploadProfileImage(file, userId = "draft") {
    return uploadFile(BUCKETS.profileImages, file, { folder: `profiles/${userId}` });
  }

  async function signedUrl(bucket, path, expiresIn = 600) {
    const supabaseClient = getClient();
    if (!supabaseClient || !bucket || !path) return "";
    const { data, error } = await supabaseClient.storage.from(bucket).createSignedUrl(path, expiresIn);
    if (error) throw error;
    return data?.signedUrl || "";
  }

  window.JuristicSupabase = {
    isEnabled,
    getClient,
    loginIdToEmail,
    signIn,
    signOut,
    loadCurrentUserContext,
    loadAppData,
    listJobs,
    saveSnapshot,
    createJob,
    assignJob,
    updateJobStatus,
    verifyCompletion,
    listLogs,
    savePermissions,
    saveSidebarOrder,
    listAccountProfiles,
    createAccountProfile,
    selectAccountProfile,
    issueProfilePinChallenge,
    verifyProfilePinChallenge,
    saveInterfacePreference,
    uploadJobAttachment,
    uploadAnnouncementFile,
    uploadProfileImage,
    signedUrl,
    BUCKETS
  };
  document.documentElement.dataset.juristicSupabaseAdapter = "loaded";
})();
