-- Synx MM2 map voting addon for Overdrive H. Load after Overdrive H.
local shared=assert(odh_shared_plugins,"Load Overdrive H before this addon")
local env=getgenv and getgenv() or _G
if env.SynxMapAddonCleanup then env.SynxMapAddonCleanup() end
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local lp=Players.LocalPlayer
local running,enabled,boost,busy=true,false,false,false
local preferred,signature,used,epoch="","",0,0
local limit=5
local function path(root,...)
    for _,name in ipairs({...}) do root=root and root:FindFirstChild(name) end
    return root
end
local function boards()
    local rows={}
    local folder=path(workspace,"Lobby","VotePads")
    for _,model in ipairs(folder and folder:GetChildren() or {}) do
        local info=model:FindFirstChild("VoteInfoGui")
        local label=path(info,"Container","MapName")
        local pad=model:FindFirstChild("Pad")
        if info and info.Enabled and label and label.Visible and label.Text~="" and pad and pad:IsA("BasePart") and pad.CanTouch then
            table.insert(rows,{name=label.Text,pad=pad,votes=path(info,"Container","Votes")})
        end
    end
    table.sort(rows,function(a,b)return a.name<b.name end)
    return rows
end
local function key(rows)
    local names={} for _,row in ipairs(rows) do table.insert(names,row.name) end
    return table.concat(names,"|")
end
-- Icon uses the documentation's sample repository path; replace with your own uploaded icon.
local tab=shared.CreateTab("MM2 Maps","/axioriasolver/testplugin/refs/heads/main/icon")
local voting=tab:AddSection("Map preference","SYNX · MM2")
voting:AddParagraph("How it works","Select a map and enable Auto vote. Reset boost respawns you to attempt extra votes while voting is open. Attempts are not guaranteed accepted votes.")
local state=voting:AddLabel("Voting closed",true)
local selection=voting:AddLabel("Preferred map: none",true)
local dropdown=voting:AddDropdown("Available maps",{},function(name)
    preferred=name;selection:SetValue("Preferred map: "..name)
end)
voting:AddTextBox("Preferred map name (optional)",function(name)
    name=name:match("^%s*(.-)%s*$")
    preferred=name;selection:SetValue("Preferred map: "..(name~="" and name or "none"))
end)
voting:AddToggle("Auto vote",function(value)enabled=value end)
local extras=tab:AddSection("Reset boost","OPTIONAL")
extras:AddParagraph("Extra attempts","Resets your character after the first vote. Runs only in the lobby. Stops when voting closes or you disable it.")
extras:AddToggle("Reset to vote again",function(value)boost=value end)
extras:AddSlider("Extra reset limit",5,20,5,function(value)limit=math.clamp(math.floor(value),5,20)end)
local progress=extras:AddLabel("Attempts this vote: 0",true)
local function launch(row)
    busy=true
    local token=epoch
    task.spawn(function()
        local char=lp.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local origin=root and root.CFrame
        local function valid()
            return running and enabled and epoch==token and preferred==row.name
                and lp:GetAttribute("Alive")==false and key(boards())==signature and signature~=""
        end
        local ok,err=pcall(function()
            if not valid() or not root or not hum or hum.Health<=0 then return end
            if used>0 then
                if not boost or used>=limit+1 then return end
                state:SetValue("Resetting for extra vote...")
                hum.Health=0
                local deadline=os.clock()+12
                repeat
                    Run.Heartbeat:Wait()
                    if not valid() or not boost then return end
                    local nextChar=lp.Character
                    local r=nextChar and nextChar:FindFirstChild("HumanoidRootPart")
                    local h=nextChar and nextChar:FindFirstChildOfClass("Humanoid")
                    if nextChar~=char and r and h and h.Health>0 then char=nextChar;root=r;hum=h;break end
                until os.clock()>=deadline
                if hum.Health<=0 then state:SetValue("Respawn timed out");return end
                origin=root.CFrame
            end
            if not valid() or lp.Character~=char or not row.pad.Parent then return end
            used+=1;progress:SetValue("Attempts this vote: "..used)
            local function count()return row.votes and tonumber(row.votes.Text:match("%d+"))end
            local before=count()
            local clearance=hum.HipHeight+root.Size.Y/2+.1
            if hum.RigType==Enum.HumanoidRigType.R6 then
                local leg=char:FindFirstChild("Left Leg");clearance+=leg and leg.Size.Y or 2
            end
            root.CFrame=row.pad.CFrame*CFrame.new(0,row.pad.Size.Y/2+clearance,0)
            root.AssemblyLinearVelocity=Vector3.zero
            local start=os.clock()
            local increased=false
            repeat
                Run.Heartbeat:Wait()
                local current=count();increased=before~=nil and current~=nil and current>before
            until not valid() or (increased and os.clock()-start>=.12) or os.clock()-start>=.8
            state:SetValue(increased and "Board count increased · vote attempt completed" or "Attempt completed · acceptance unconfirmed")
        end)
        if root and root.Parent and origin and lp.Character==char and hum and hum.Health>0 and lp:GetAttribute("Alive")==false then
            root.CFrame=origin;root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
        end
        if not ok then warn("Synx map addon: ",err);state:SetValue("Vote attempt failed") end
        busy=false
    end)
end
local elapsed=0
local connection=Run.Heartbeat:Connect(function(dt)
    elapsed+=dt;if elapsed<.1 or not running then return end;elapsed=0
    local rows=boards();local current=key(rows)
    if current~=signature then
        signature=current;epoch+=1;used=0
        local names={}for _,row in ipairs(rows) do table.insert(names,row.name) end
        dropdown:ChangeItems(names)
        progress:SetValue("Attempts this vote: 0")
        state:SetValue(current=="" and "Voting closed" or "Voting open · select a preferred map")
    end
    if busy or not enabled or lp:GetAttribute("Alive")~=false then return end
    if used>0 and (not boost or used>=limit+1) then return end
    for _,row in ipairs(rows) do if row.name==preferred then launch(row);break end end
end)
env.SynxMapAddonCleanup=function()running=false;enabled=false;epoch+=1;connection:Disconnect()end
shared.Notify("Synx MM2 map addon loaded. Auto vote is OFF.",3)
