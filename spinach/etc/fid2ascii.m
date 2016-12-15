% Writes free induction decays into ASCII files.
%
% <http://spindynamics.org/wiki/index.php?title=Fid2ascii.m>

function fid2ascii(file_name,fid)

% Check consistency
grumble(fid)

% Open the file for writing
file_id=fopen(file_name,'w');

% Decide data dimensions
if isvector(fid)
    
    % Interleave real and imaginary parts
    for n=1:numel(fid)
        fprintf(file_id,'%d %12.8E \n',[n real(fid(n))]);
    end
    for n=1:numel(fid)
        fprintf(file_id,'%d %12.8E \n',[(n+numel(fid)) imag(fid(n))]);
    end
    
elseif ismatrix(fid)
    
    % Write out the fid
    for k=1:size(fid,2)
        
        % Interleave real and imaginary parts
        for n=1:size(fid,1)
            fprintf(file_id,'%d %d %12.8E \n',[n k real(fid(n,k))]);
        end
        for n=1:size(fid,1)
            fprintf(file_id,'%d %d %12.8E \n',[(n+size(fid,1)) k imag(fid(n,k))]);
        end
        
    end
    
elseif ndims(fid)==3
    
    % Write out the fid
    for m=1:size(fid,3)
        for k=1:size(fid,2)
            
            % Interleave real and imaginary parts
            for n=1:size(fid,1)
                fprintf(file_id,'%d %d %d %12.8E \n',[n k m real(fid(n,k,m))]);
            end
            for n=1:size(fid,1)
                fprintf(file_id,'%d %d %d %12.8E \n',[(n+size(fid,1)) k m imag(fid(n,k,m))]);
            end
            
        end
    end
    
else
    
    % Complain and bomb out
    error('insupported data dimensionality.');
    
end
        
% Close the file
fclose(file_id);
        
end

% Consistency enforcement
function grumble(fid)
if ~isnumeric(fid), error('fid must be numeric.'); end
end

% To be a - I don't know if this phrase is an oxymoron - but to be a sensible
% theologian, or at least one who has a pretense of being scholarly, you at
% least have to have some vague idea of what's going on in science, how old
% the universe is, etc. But to do science you don't have to know anything
% about theology. Scientists don't read theology, they don't read philosophy,
% it doesn't make any difference to what they're doing - for better or worse,
% it may not be a value judgment, but it's true.
% 
% Lawrence Krauss

