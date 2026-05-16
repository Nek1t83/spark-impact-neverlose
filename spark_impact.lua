local rand_f      = utils.random_float
local sin         = math.sin
local cos         = math.cos
local sqrt        = math.sqrt
local floor       = math.floor
local mmax        = math.max
local mabs        = math.abs
local pi2         = math.pi * 2
local vec         = vector
local render_line = render.line
local render_circ = render.circle

local m           = ui.create('Spark Impact')
local mi_on       = m:switch('Включить эффект', true)
local mi_self     = m:switch('Только мои выстрелы', true)
local mi_color    = m:color_picker('Цвет искр', color(255, 220, 80, 255))
local mi_count    = m:slider('Количество искр', 8, 80, 35, 1)
local mi_speed    = m:slider('Разлёт',          100, 900, 420, 1)
local mi_grav     = m:slider('Гравитация',      0,   1500, 700, 1)
local mi_life     = m:slider('Длительность',    2,   20,   9,   10, ' с')
local mi_tail     = m:slider('Длина искр',      1,   25,   8,   100, ' с')
local mi_thick    = m:slider('Толщина искр',    1,   6,    2,   1, ' px')
local mi_flash    = m:switch('Вспышка в центре', true)
local mi_flash_sz = m:slider('Размер вспышки',  2,   20,   8,   1, ' px')
local mi_gradient = m:switch('Градиент (белый центр)', true)
local mi_3d       = m:switch('3D-перспектива', true)
local mi_collide  = m:switch('Отскок от поверхностей', true)
local mi_bounce   = m:slider('Сила отскока', 0, 80, 35, 100)

local sparks     = {}
local sparks_n   = 0
local flashes    = {}
local flashes_n  = 0
local MAX_SPARKS = 600
local FLASH_TIME = 0.06

local function draw_thick_line(p1, p2, clr, thickness)
    render_line(p1, p2, clr)
    if thickness <= 1 then return end
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    local len2 = dx * dx + dy * dy
    if len2 < 0.5 then return end
    local inv = 1 / sqrt(len2)
    local nx = -dy * inv
    local ny = dx * inv
    local half = floor(thickness * 0.5)
    for k = 1, half do
        local ox, oy = nx * k, ny * k
        render_line(vec(p1.x + ox, p1.y + oy), vec(p2.x + ox, p2.y + oy), clr)
        render_line(vec(p1.x - ox, p1.y - oy), vec(p2.x - ox, p2.y - oy), clr)
    end
end

local function add_spark(x, y, z, vx, vy, vz, born, life)
    sparks_n = sparks_n + 1
    sparks[sparks_n] = {
        x = x, y = y, z = z,
        vx = vx, vy = vy, vz = vz,
        born = born, life = life,
    }
end

local function kill_spark(i)
    sparks[i] = sparks[sparks_n]
    sparks[sparks_n] = nil
    sparks_n = sparks_n - 1
end

local function kill_flash(i)
    flashes[i] = flashes[flashes_n]
    flashes[flashes_n] = nil
    flashes_n = flashes_n - 1
end

events.bullet_impact:set(function(e)
    if not mi_on:get() then return end

    if mi_self:get() then
        local me = entity.get_local_player()
        if not me then return end
        local shooter = entity.get(e.userid, true)
        if shooter ~= me then return end
    end

    if sparks_n >= MAX_SPARKS then return end

    local ox, oy, oz = e.x, e.y, e.z
    local now        = globals.realtime
    local count      = mi_count:get()
    local base_speed = mi_speed:get()
    local base_life  = mi_life:get() / 10

    if mi_flash:get() then
        flashes_n = flashes_n + 1
        flashes[flashes_n] = { x = ox, y = oy, z = oz, born = now }
    end

    local left = MAX_SPARKS - sparks_n
    if count > left then count = left end
    for _ = 1, count do
        local theta = rand_f(0, pi2)
        local cz    = rand_f(-1, 1)
        local sxy   = sqrt(1 - cz * cz)
        local dx    = sxy * cos(theta)
        local dy    = sxy * sin(theta)
        local dz    = cz

        local s    = base_speed * rand_f(0.55, 1.0)
        local life = base_life  * rand_f(0.75, 1.0)
        add_spark(ox, oy, oz, dx * s, dy * s, dz * s, now, life)
    end
end)

events.render:set(function()
    if sparks_n == 0 and flashes_n == 0 then return end

    local now = globals.realtime
    local dt  = globals.frametime
    if dt > 0.1 then dt = 0.1 end

    local grav = mi_grav:get() * dt
    local drag = 1 - 1.2 * dt
    if drag < 0 then drag = 0 end

    local c           = mi_color:get()
    local cr, cg, cb  = c.r, c.g, c.b
    local wr          = 255 - cr
    local wg          = 255 - cg
    local wb          = 255 - cb

    local tail       = mi_tail:get() / 100
    local thick      = mi_thick:get()
    local flsz       = mi_flash_sz:get()
    local flsz_inner = flsz * 0.35
    if flsz_inner < 1 then flsz_inner = 1 end
    local use_grad = mi_gradient:get()
    local use_3d   = mi_3d:get()
    local use_coll = mi_collide:get()
    local bounce   = mi_bounce:get() / 100

    local cx, cy, cz
    if use_3d then
        local cam_pos = render.camera_position()
        cx, cy, cz = cam_pos.x, cam_pos.y, cam_pos.z
    end

    local me_ent
    if use_coll then me_ent = entity.get_local_player() end

    local i = 1
    while i <= flashes_n do
        local f   = flashes[i]
        local age = now - f.born
        if age >= FLASH_TIME then
            kill_flash(i)
        else
            local scr = vec(f.x, f.y, f.z):to_screen()
            if scr then
                local a = floor(255 * (1 - age / FLASH_TIME))
                render_circ(scr, color(cr, cg, cb, a), flsz, 0, 1)
                render_circ(scr, color(255, 255, 255, a), flsz_inner, 0, 1)
            end
            i = i + 1
        end
    end

    local SEGS           = 4
    local INV_SEG        = 1 / SEGS
    local GRAD_INTENSITY = 0.55
    i = 1
    while i <= sparks_n do
        local s   = sparks[i]
        local age = now - s.born
        if age >= s.life then
            kill_spark(i)
        else
            s.vx = s.vx * drag
            s.vy = s.vy * drag
            s.vz = (s.vz - grav) * drag

            local nx_pos = s.x + s.vx * dt
            local ny_pos = s.y + s.vy * dt
            local nz_pos = s.z + s.vz * dt

            if use_coll then
                local vlen2 = s.vx * s.vx + s.vy * s.vy + s.vz * s.vz
                if vlen2 > 900 then
                    local tr = utils.trace_line(
                        vec(s.x, s.y, s.z),
                        vec(nx_pos, ny_pos, nz_pos),
                        me_ent
                    )
                    if tr and tr.fraction < 1 and tr.plane and not tr.all_solid then
                        local nrm            = tr.plane.normal
                        local nnx, nny, nnz  = nrm.x, nrm.y, nrm.z
                        local dotp           = s.vx * nnx + s.vy * nny + s.vz * nnz
                        s.vx = (s.vx - 2 * dotp * nnx) * bounce
                        s.vy = (s.vy - 2 * dotp * nny) * bounce
                        s.vz = (s.vz - 2 * dotp * nnz) * bounce
                        local ep = tr.end_pos
                        nx_pos = ep.x + nnx * 0.5
                        ny_pos = ep.y + nny * 0.5
                        nz_pos = ep.z + nnz * 0.5
                        if s.vx * s.vx + s.vy * s.vy + s.vz * s.vz < 100 then
                            s.vx, s.vy, s.vz = 0, 0, 0
                        end
                    end
                end
            end

            s.x = nx_pos
            s.y = ny_pos
            s.z = nz_pos

            local hx, hy, hz = s.x, s.y, s.z
            local tx_ = hx - s.vx * tail
            local ty_ = hy - s.vy * tail
            local tz_ = hz - s.vz * tail

            local p_head = vec(hx, hy, hz):to_screen()
            local p_tail = vec(tx_, ty_, tz_):to_screen()
            if p_head and p_tail then
                local pscale = 1.0
                if use_3d then
                    local ddx  = hx - cx
                    local ddy  = hy - cy
                    local ddz  = hz - cz
                    local dist = sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
                    if dist < 100 then dist = 100 end
                    pscale = 500 / dist
                    if pscale > 2.2 then pscale = 2.2 end
                    if pscale < 0.3 then pscale = 0.3 end
                end

                local life_frac = 1 - age / s.life
                local a_main    = floor(255 * life_frac)
                local th_line   = mmax(1, floor(thick * pscale))

                if use_grad then
                    local dx_w = hx - tx_
                    local dy_w = hy - ty_
                    local dz_w = hz - tz_
                    local prev = p_tail
                    for k = 1, SEGS do
                        local t = k * INV_SEG
                        local p_n
                        if k == SEGS then
                            p_n = p_head
                        else
                            p_n = vec(tx_ + dx_w * t,
                                      ty_ + dy_w * t,
                                      tz_ + dz_w * t):to_screen()
                        end
                        if prev and p_n then
                            local mid_t = t - INV_SEG * 0.5
                            local w = (1 - mabs(mid_t - 0.5) * 2) * GRAD_INTENSITY
                            if w < 0 then w = 0 end
                            local sr = cr + wr * w
                            local sg = cg + wg * w
                            local sb = cb + wb * w
                            draw_thick_line(prev, p_n, color(sr, sg, sb, a_main), th_line)
                        end
                        prev = p_n
                    end
                else
                    draw_thick_line(p_head, p_tail, color(cr, cg, cb, a_main), th_line)
                end

                local cap_r   = th_line * 0.5
                if cap_r < 1 then cap_r = 1 end
                local cap_clr = color(cr, cg, cb, a_main)
                render_circ(p_tail, cap_clr, cap_r, 0, 1)
                render_circ(p_head, cap_clr, cap_r, 0, 1)
            end
            i = i + 1
        end
    end
end)

events.shutdown:set(function()
    sparks, sparks_n   = {}, 0
    flashes, flashes_n = {}, 0
end)
